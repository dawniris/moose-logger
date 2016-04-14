#!/usr/bin/env bundle exec ruby
require 'optparse'
require 'sqlite3'

STATUS=['PASS', 'FAIL', 'INCOMPLETE', 'SKIPPED']
DEFAULT_OPTIONS={
  :help      => false,
  :days_back => nil,
  :db        => 'moose_results.db',
  :latest    => false,
}
SEPERATOR="**************************************************************************"
TABLE_SEPERATOR="        "
JUST=50
SJUST=12
@options=DEFAULT_OPTIONS
@db=nil

# Returns options parser object
def options_parser
  optparse = OptionParser.new do|opts|
    # Set a banner
    opts.banner = "Usage: #{File.basename($0)} [options...]"

    opts.on '-d NUM', '--days-back NUM',
            'how many days into the past to use for report generation' do |days_back|
      @options[:days_back] = days_back
    end

    opts.on '-l', '--latest',
            'how many days into the past to use for report generation' do
      @options[:latest] = true
    end

    opts.on '--db DATABASE_NAME',
            'sqlite3 database to push data to' do |dbname|
      @options[:db] = dbname
    end

    opts.on '-h', '--help' do
      @options[:help] = true
    end
  end
  optparse
end

def open_db(name)
  @db = SQLite3::Database.open name
end

def number_of_test_runs(time_clause)
  query_str = "select count(distinct(run_date)) as num
  from test_results
  where test_results.test_id >= 0
  %s;"
  res = @db.execute(query_str % time_clause)
  num_tests = res.first.first
  formatted_res = ""
  formatted_res +=  SEPERATOR
  formatted_res += "\nTest runs in range : #{num_tests}\n"
  formatted_res
end

def status_per_test_run(time_clause)
  query_str = "select test_results.run_date, count(*), #{STATUS.map{ |s| "count(CASE WHEN status = '#{s}' THEN 1 ELSE NULL END)"}.join(', ')}
  from test_results
  where test_results.test_result_id >= 0
  %s
  group by test_results.run_date
  order by test_results.run_date;"
  res = @db.execute(query_str % time_clause)
  formatted_res = ""
  formatted_res +=  SEPERATOR
  formatted_res += "\nResults per test run\n"
  header = "  |  #{"Date".ljust(JUST)}|  #{"Total".ljust(SJUST)}|#{STATUS.map{ |s| "  #{s.ljust(SJUST)}|"}.join('')}\n"
  formatted_res += header
  table_line = "  " + "-"*(header.length-3) + "\n"
  formatted_res += table_line
  res.each do |row|
    formatted_res += "  |  #{row[0].ljust(JUST)}|  #{row[1].to_s.ljust(SJUST)}|"
    formatted_res += row[2..-1].map{ |val| "  #{val.to_s.ljust(SJUST)}" }.join("|")
    formatted_res += "|\n"
    formatted_res += table_line
  end
  formatted_res
end

# find the index of the nth occurrence of the given character in the given string
def nthoccurrence str, char, nth
  res = str.length
  nth = nth - 1
  chunks = str.split(char)
  if !(chunks.length == 1)
    res = chunks[nth..-1].join(char).index(char) + chunks[0..nth-1].join(char).length + 1
  end
  res
end

def most_frequent_exception_names(time_clause)
  query_str = "select count(*) as num, group_concat(distinct tests.name), exception_name
  from test_results, tests
  where tests.test_id = test_results.test_id
  and exception_trace != ''
  %s
  group by exception_name
  order by num DESC
  limit 10;"
  res = @db.execute(query_str % time_clause)
  formatted_res = ""
  formatted_res +=  SEPERATOR
  formatted_res += "\nMost frequent exception names\n"
  header = "  |  #{"Occurrences".ljust(JUST)}#{TABLE_SEPERATOR}|  #{"Tests".ljust(JUST)}|\n"
  formatted_res += header
  table_line = "  " + "-"*(header.length-3) + "\n"
  formatted_res += table_line
  res.each do |row|
    formatted_res += "  |  #{row[0].to_s.ljust(JUST)}#{TABLE_SEPERATOR}|  #{"".ljust(JUST)}|\n"
    row[1].split(",").each do |tline|
      formatted_res += "  |  #{"".ljust(JUST)}#{TABLE_SEPERATOR}|      #{tline.to_s.ljust(JUST-4)}\n"
    end
    formatted_res += "  |    Name: \n"
    formatted_res += "  |      #{row[2].to_s.ljust(JUST-4)}\n"
    formatted_res += table_line
  end
  formatted_res

end

def most_frequent_exception_traces(time_clause)
  # helper function!
  @db.create_function "nthoccurrence", 3 do |func, a, b, c|
    func.result = nthoccurrence(a, b, c)
  end

  query_str = "select count(*) as num, group_concat(distinct tests.name), substr(exception_trace, 1, nthoccurrence(exception_trace, \"\\n\", 8) + 1) as top_of_trace
  from test_results, tests
  where tests.test_id = test_results.test_id
  and exception_trace != ''
  %s
  group by top_of_trace
  order by num DESC
  limit 10;"
  res = @db.execute(query_str % time_clause)
  formatted_res = ""
  formatted_res +=  SEPERATOR
  formatted_res += "\nMost frequent exception traces\n"
  header = "  |  #{"Occurrences".ljust(JUST)}#{TABLE_SEPERATOR}|  #{"Tests".ljust(JUST)}|\n"
  formatted_res += header
  table_line = "  " + "-"*(header.length-3) + "\n"
  formatted_res += table_line
  res.each do |row|
    formatted_res += "  |  #{row[0].to_s.ljust(JUST)}#{TABLE_SEPERATOR}|  #{"".ljust(JUST)}|\n"
    row[1].split(",").each do |tline|
      formatted_res += "  |  #{"".ljust(JUST)}#{TABLE_SEPERATOR}|      #{tline.to_s.ljust(JUST-4)}\n"
    end
    formatted_res += "  |    Trace: \n"
    row[2].split("\\n").each do |tline|
      formatted_res += "  |      #{tline.to_s.ljust(JUST-4)}\n"
    end
    formatted_res += table_line
  end
  formatted_res
end

def tests_with_most_failures(time_clause)
  query_str = "select count(*) as num, suites.name, test_groups.name, tests.name
  from test_results, tests, test_groups, suites
  where test_results.test_id = tests.test_id
  and test_groups.test_id = tests.test_id
  and suites.test_group_id = test_groups.test_group_id
  and test_results.status = \"FAIL\"
  %s
  group by tests.test_id
  order by num DESC
  limit 10;"
  res = @db.execute(query_str % time_clause)
  formatted_res = ""
  formatted_res +=  SEPERATOR
  formatted_res += "\nTests with most failures\n"
  header = "  |  #{"Fails".ljust(SJUST)}|  #{"Suite".ljust(SJUST)}|  #{"Group".ljust(JUST)}|  #{"Test Name".ljust(JUST)}|\n"
  formatted_res += header
  table_line = "  " + "-"*(header.length-3) + "\n"
  formatted_res += table_line
  res.each do |row|
    formatted_res += "  |  #{row[0].to_s.ljust(SJUST)}|  #{row[1].to_s.ljust(SJUST)}|  #{row[2].to_s.ljust(JUST)}|  #{row[3].to_s.ljust(JUST)}|\n"
    formatted_res += table_line
  end
  formatted_res
end

def tests_that_always_fail(time_clause)
  query_str = "select count(distinct(run_date)) as num
  from test_results
  where test_results.test_id >= 0
  %s;"
  res = @db.execute(query_str % time_clause)
  runs = res.first.first
  query_str = "select num, suite_name, test_group_name, test_name from
    (select count(*) as num, suites.name as suite_name, test_groups.name as test_group_name, tests.name as test_name
    from test_results, tests, test_groups, suites
    where test_results.test_id = tests.test_id
    and test_groups.test_id = tests.test_id
    and suites.test_group_id = test_groups.test_group_id
    and test_results.status = \"FAIL\"
    %s
    group by tests.test_id
    order by num DESC)
    where num >= #{runs};
  ;"
  res = @db.execute(query_str % time_clause)
  formatted_res = ""
  formatted_res +=  SEPERATOR
  formatted_res += "\nTests that only FAILed in selected time range\n"
  header = "  |  #{"Fails".ljust(SJUST)}|  #{"Suite".ljust(SJUST)}|  #{"Group".ljust(JUST)}|  #{"Test Name".ljust(JUST)}|\n"
  formatted_res += header
  table_line = "  " + "-"*(header.length-3) + "\n"
  formatted_res += table_line
  res.each do |row|
    formatted_res += "  |  #{row[0].to_s.ljust(SJUST)}|  #{row[1].to_s.ljust(SJUST)}|  #{row[2].to_s.ljust(JUST)}|  #{row[3].to_s.ljust(JUST)}|\n"
    formatted_res += table_line
  end
  formatted_res

end

def greatest_avg_test_execution_time(time_clause)
  query_str = "select avg(test_results.elapsed_time) as num, suites.name, test_groups.name, tests.name
  from test_results, tests, test_groups, suites
  where tests.test_id = test_results.test_id
  and suites.test_group_id = test_groups.test_group_id
  and test_groups.test_id = tests.test_id
  %s
  and test_results.elapsed_time != (select max(tr_inner.elapsed_time) from test_results tr_inner where test_results.test_id = tr_inner.test_id group by tr_inner.test_id)
  group by test_results.test_id
  order by num DESC
  limit 10;"
  res = @db.execute(query_str % time_clause)
  formatted_res = ""
  formatted_res +=  SEPERATOR
  formatted_res += "\nTests with greatest execution time - Average Excluding Max\n"
  header = "  |  #{"Avg (s)".ljust(SJUST)}|  #{"Suite".ljust(SJUST)}|  #{"Group".ljust(JUST)}|  #{"Test Name".ljust(JUST)}|\n"
  formatted_res += header
  table_line = "  " + "-"*(header.length-3) + "\n"
  formatted_res += table_line
  res.each do |row|
    formatted_res += "  |  #{row[0].to_f.round(2).to_s.ljust(SJUST)}|  #{row[1].ljust(SJUST)}|  #{row[2].ljust(JUST)}|  #{row[3].to_s.ljust(JUST)}|\n"
    formatted_res += table_line
  end
  formatted_res
end

def avg_status_per_test_group(status, time_clause)
  query_str = "select avg(fail_count) as num, suite_name, test_group_name
  from ( select count(*) as fail_count, test_groups.name as test_group_name, suites.name as suite_name
    from tests, test_groups, test_results, suites
    where test_groups.test_id = tests.test_id
    and suites.test_group_id = test_groups.test_group_id
    and test_results.test_id = tests.test_id
    and test_results.status = \"#{status}\"
    %s
    group by test_groups.name, test_results.run_date
       )
  group by test_group_name
  order by num DESC;
  "
  res = @db.execute(query_str % time_clause)
  formatted_res = ""
  formatted_res +=  SEPERATOR
  formatted_res += "\nAverage Number of Status '#{status}'(s) per Test Group\n"
  header = "  |  #{"Avg".ljust(SJUST)}|  #{"Suite".ljust(SJUST)}|  #{"Test Group Name".ljust(JUST)}|\n"
  formatted_res += header
  table_line = "  " + "-"*(header.length-3) + "\n"
  formatted_res += table_line
  res.each do |row|
    formatted_res += "  |  #{row[0].to_f.round(2).to_s.ljust(SJUST)}|  #{row[1].to_s.ljust(SJUST)}|  #{row[2].to_s.ljust(JUST)}|\n"
    formatted_res += table_line
  end
  formatted_res
end

def max_run_date
  query_str = "select max(test_results.run_date)
  from test_results;"
  res = @db.execute(query_str)
  res.first.first
end

def collect_from_db(days_back, latest)
  res = ""
  time_clause = ""
  if !latest
    if days_back
      time_clause = "and test_results.run_date between datetime('now', '-%d days') AND datetime('now')" % days_back
    end
  else
    time_clause = "and test_results.run_date = \"#{max_run_date}\""
  end
  res += number_of_test_runs(time_clause)
  res += status_per_test_run(time_clause)
  res += most_frequent_exception_names(time_clause)
  res += most_frequent_exception_traces(time_clause)
  res += tests_with_most_failures(time_clause)
  res += tests_that_always_fail(time_clause)
  res += greatest_avg_test_execution_time(time_clause)
  res += avg_status_per_test_group('FAIL', time_clause)
  res
end

optparse = options_parser
optparse.parse(ARGV)
if @options[:help]
  puts optparse.help
  exit
end
if @options[:days_back] && @options[:latest]
  puts "Cannot combine --days-back with --latest!"
  exit
end
puts "#{SEPERATOR}\n"*3
puts "Automoose Report for #{Time.now().strftime("%Y-%m-%d %H:%M:%S")}"
time_clause = ""
if @options[:days_back]
  time_clause = "Last %d days recorded test results" % @options[:days_back]
elsif @options[:latest]
  time_clause = "Latest recorded test results"
else
  time_clause = "All recorded test results"
end
puts time_clause
open_db(@options[:db])
results = collect_from_db(@options[:days_back], @options[:latest])
puts results
@db.close
