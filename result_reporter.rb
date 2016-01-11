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
JUST=40
SJUST=10
TABLE_LINE="   ----------------------------------------------------------------------------------------------\n"
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
  query_str = "select test_results.run_date, #{STATUS.map{ |s| "count(CASE WHEN status = '#{s}' THEN 1 ELSE NULL END)"}.join(', ')}
  from test_results
  where test_results.test_result_id >= 0
  %s
  group by test_results.run_date
  order by test_results.run_date;"
  res = @db.execute(query_str % time_clause)
  formatted_res = ""
  formatted_res +=  SEPERATOR
  formatted_res += "\nResults per test run\n"
  formatted_res += "  |  #{"Date".ljust(JUST)}|#{STATUS.map{ |s| "  #{s.ljust(SJUST)}|"}.join('')}"
  formatted_res += "\n"
  formatted_res += TABLE_LINE
  res.each do |row|
    formatted_res += "  |  #{row[0].ljust(JUST)}|"
    formatted_res += row[1..-1].map{ |val| "  #{val.to_s.ljust(SJUST)}" }.join("|")
    formatted_res += "|\n"
    formatted_res += TABLE_LINE
  end
  formatted_res
end

def most_frequent_exception_traces(time_clause)
  query_str = "select count(*) as num, exception_trace, group_concat(distinct tests.name)
  from test_results, tests
  where test_results.exception_trace != \"\"
  and tests.test_id = test_results.test_id
  %s
  group by exception_trace
  order by num DESC
  limit 5;"
  res = @db.execute(query_str % time_clause)
  formatted_res = ""
  formatted_res +=  SEPERATOR
  formatted_res += "\nMost frequent exception traces\n"
  formatted_res += "  |  #{"Occurences".ljust(JUST)}#{TABLE_SEPERATOR}|  #{"Tests".ljust(JUST)}|\n"
  formatted_res += TABLE_LINE
  res.each do |row|
    formatted_res += "  |  #{row[0].to_s.ljust(JUST)}#{TABLE_SEPERATOR}|  #{"Observed in:".ljust(JUST)}|\n"
    row[2].split(',').each do |tn|
      formatted_res += "  |  #{" ".ljust(JUST)}#{TABLE_SEPERATOR}|   #{tn.ljust(JUST-1)}|\n"
    end
    formatted_res += "  |    Trace: \n"
    row[1].split("\\n").each do |tline|
      formatted_res += "  |      #{tline.to_s.ljust(JUST-4)}\n"
    end
    formatted_res += TABLE_LINE
  end
  formatted_res
end

def tests_with_most_failures(time_clause)
  query_str = "select count(*) as num, name
  from test_results, tests
  where test_results.test_id = tests.test_id
  and test_results.status = \"FAIL\"
  %s
  group by tests.test_id
  order by num DESC
  limit 5;"
  res = @db.execute(query_str % time_clause)
  formatted_res = ""
  formatted_res +=  SEPERATOR
  formatted_res += "\nTests with most failures\n"
  formatted_res += "  |  #{"Number of failures".ljust(JUST)}#{TABLE_SEPERATOR}|  #{"Test Name".ljust(JUST)}|\n"
  formatted_res += TABLE_LINE
  res.each do |row|
    formatted_res += "  |  #{row[0].to_s.ljust(JUST)}#{TABLE_SEPERATOR}|  #{row[1].to_s.ljust(JUST)}|\n"
    formatted_res += TABLE_LINE
  end
  formatted_res
end

def greatest_avg_test_execution_time(time_clause)
  query_str = "select avg(test_results.elapsed_time) as num, tests.name
  from test_results, tests 
  where tests.test_id = test_results.test_id  
  %s
  and test_results.elapsed_time != (select max(tr_inner.elapsed_time) from test_results tr_inner where test_results.test_id = tr_inner.test_id group by tr_inner.test_id)
  group by test_results.test_id 
  order by num DESC 
  limit 10;"
  res = @db.execute(query_str % time_clause)
  formatted_res = ""
  formatted_res +=  SEPERATOR
  formatted_res += "\nTests with greatest execution time\n"
  formatted_res += "  |  #{"Avg Excluding Max Execution time (s)".ljust(JUST)}#{TABLE_SEPERATOR}|  #{"Test Name".ljust(JUST)}|\n"
  formatted_res += TABLE_LINE
  res.each do |row|
    formatted_res += "  |  #{row[0].to_f.round(2).to_s.ljust(JUST)}#{TABLE_SEPERATOR}|  #{row[1].to_s.ljust(JUST)}|\n"
    formatted_res += TABLE_LINE
  end
  formatted_res
end

def avg_status_per_test_group(status, time_clause)
  query_str = "select avg(fail_count) as num, test_group_name
  from ( select count(*) as fail_count, test_groups.name as test_group_name
    from tests, test_groups, test_results 
    where test_groups.test_id = tests.test_id
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
  formatted_res += "  |  #{"Avg Number of '#{status}'(s)".ljust(JUST)}#{TABLE_SEPERATOR}|  #{"Test Group Name".ljust(JUST)}|\n"
  formatted_res += TABLE_LINE
  res.each do |row|
    formatted_res += "  |  #{row[0].to_f.round(2).to_s.ljust(JUST)}#{TABLE_SEPERATOR}|  #{row[1].to_s.ljust(JUST)}|\n"
    formatted_res += TABLE_LINE
  end
  formatted_res
end

def test_groups_ordered_by_failures(time_clause)
  query_str = "select count(*) as num, test_groups.name
  from test_groups, tests, test_results
  where test_groups.test_id = tests.test_id
  and test_results.test_id = tests.test_id
  and test_results.status = \"FAIL\"
  %s
  group by test_groups.name
  order by num DESC;"
  res = @db.execute(query_str % time_clause)
  formatted_res = ""
  formatted_res +=  SEPERATOR
  formatted_res += "\nTests Groups with most failures\n"
  formatted_res += "  |  #{"Sum Total Number of Failures".ljust(JUST)}#{TABLE_SEPERATOR}|  #{"Test Group Name".ljust(JUST)}|\n"
  formatted_res += TABLE_LINE
  res.each do |row|
    formatted_res += "  |  #{row[0].to_s.ljust(JUST)}#{TABLE_SEPERATOR}|  #{row[1].to_s.ljust(JUST)}|\n"
    formatted_res += TABLE_LINE
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
  # NOTE - disabled for now, not sure of value of this data
  #res += most_frequent_exception_traces(time_clause)
  res += tests_with_most_failures(time_clause)
  res += greatest_avg_test_execution_time(time_clause)
  res += avg_status_per_test_group('FAIL', time_clause)
  # NOTE - disabled for now, not sure of value of this data
  #res += test_groups_ordered_by_failures(time_clause)
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
