#!/usr/bin/env bundle exec ruby
require 'optparse'
require 'sqlite3'

DEFAULT_OPTIONS={
  :help      => false,
  :days_back => nil,
  :db        => 'moose_results.db',
  :latest    => false,
}
SEPERATOR="**************************************************************************"
TABLE_SEPERATOR="        "
JUST=40
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

def fails_per_test_run(time_clause)
  query_str = "select test_results.run_date, count(tests.name), group_concat(distinct tests.name)
  from test_results,tests
  where tests.test_id = test_results.test_id
  and test_results.status = \"FAIL\"
  %s
  group by test_results.run_date;
  order by test_result.run_date"
  res = @db.execute(query_str % time_clause)
  formatted_res = ""
  formatted_res +=  SEPERATOR
  formatted_res += "\nFailures per test run\n"
  formatted_res += "  |  #{"Date".ljust(JUST)}#{TABLE_SEPERATOR}|  #{"Fails".ljust(JUST)}|\n"
  formatted_res += TABLE_LINE
  res.each do |row|
    formatted_res += "  |  #{row[0].to_s.ljust(JUST)}#{TABLE_SEPERATOR}|  #{row[1].to_s.ljust(JUST)}|\n"
    formatted_res += "  |    Failed tests: \n"
    row[2].split(',').each do |tn|
      formatted_res += "  |      #{tn.to_s.ljust(JUST-4)}\n"
    end
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
  formatted_res += "  |  #{"Number of Failures".ljust(JUST)}#{TABLE_SEPERATOR}|  #{"Test Group Name".ljust(JUST)}|\n"
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
  res += fails_per_test_run(time_clause)
  res += most_frequent_exception_traces(time_clause)
  res += tests_with_most_failures(time_clause)
  res += test_groups_ordered_by_failures(time_clause)
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
