#!/usr/bin/env bundle exec ruby
require 'optparse'
require 'yaml'
require 'sqlite3'

DEFAULT_OPTIONS={
  :help  => false,
  :file  => nil,
  :dir   => nil,
  :db    => 'moose_results.db',
}
@options=DEFAULT_OPTIONS
@db=nil

# Returns options parser object
def options_parser
  optparse = OptionParser.new do|opts|
    # Set a banner
    opts.banner = "Usage: #{File.basename($0)} [options...]"

    opts.on '-d', '--dir DIR',
            'directory of yml files to process' do |dirname|
      @options[:dir] = dirname
    end

    opts.on '-f', '--file FILE',
            'single file to process' do |filename|
      @options[:file] = filename
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

def insert_to_db(run_date, suite, test_group, data_hash)
  data_hash[test_group].each_pair do |res_key, res_val|
    # make sure that we have an entry for this test
    test_id = @db.execute("SELECT test_id FROM tests WHERE name = \"#{res_key}\";")
    if test_id.kind_of?(Array) && !test_id.empty?
      test_id = test_id.first.first
    else
      @db.execute("INSERT INTO tests(name, description)
                   VALUES (?,?)", [res_key, res_val["description"]])
      test_id = @db.last_insert_row_id
    end
    # make sure that we have an entry for this test_group for this test_id
    test_group_id = @db.execute("SELECT test_group_id from test_groups WHERE name = \"#{test_group}\" and test_id = #{test_id};")
    if test_group_id.kind_of?(Array) && !test_group_id.empty?
      test_group_id = test_group_id.first.first
    else
      @db.execute("INSERT INTO test_groups(name, test_id)
                   VALUES (?,?)", [test_group, test_id])
      test_group_id = @db.last_insert_row_id
    end
    # make sure that we have an entry for this suite
    suite_id = @db.execute("SELECT suite_id FROM suites WHERE name = \"#{suite}\" and test_group_id = #{test_group_id};")
    if suite_id.kind_of?(Array) && !suite_id.empty?
      suite_id = suite_id.first.first
    else
      @db.execute("INSERT INTO suites(name, test_group_id)
                   VALUES (?,?)", [suite, test_group_id])
      suite_id = @db.last_insert_row_id
    end
    # time to add the test results
    res_val[:exception] ||= {}
    exception_name = ""
    exception_trace = ""
    exception = res_val[:exception].first
    if !exception.nil?
      exception_name = exception[0]
      exception_trace = exception[1].join('\n')
    end
    # if we've already seen a test run on this date then ignore this one
    test_result_id = @db.execute("SELECT test_result_id FROM test_results WHERE test_id = #{test_id} AND run_date = \"#{run_date}\";")
    if test_result_id.kind_of?(Array) && !test_result_id.empty?
      puts "    SKIP duplicate #{run_date} result for #{suite} - #{test_group} - #{res_key}"
      next
    end
    puts "    ADD #{run_date} result for #{suite} - #{test_group} - #{res_key}"
    @db.execute("INSERT INTO test_results(status, elapsed_time, exception_name, exception_trace, test_id, run_date)
                 VALUES (?,?,?,?,?,?)", [res_val[:status], res_val[:elapsed], exception_name, exception_trace, test_id, run_date])
  end
end

def process_file(f)
  puts "FILE: \"#{f}\""

  suite = nil
  test_group = nil
  yaml_chunk = ""
  # pull the run date out of the file name
  m = /^.*(\d\d\d\d-\d\d-\d\d).*(\d\d:\d\d)$/.match(f)
  run_date = "#{m[1]} #{m[2]}:00"
  File.foreach( f ) do |line|
    # garbage line, throw it away
    if line =~ /^(=======================)|(---)|(--- {})|(%.*%)$/
      next
    end
    # empty line, throw it away
    if line =~ /^$/
      next
    end
    # find a header
    m = /^(\w*) - (\w*)$/.match(line)
    if !m.nil?
      # process a yaml_chunk if we have one
      if !yaml_chunk.empty?
        data_hash = YAML.load(yaml_chunk)
        # insert data into database
        insert_to_db(run_date, suite, test_group, data_hash)
      end
      # get the new data and start over
      yaml_chunk = ""
      suite = m[1]
      test_group = m[2]
      puts "  #{suite} - #{test_group}"
    else
      # do a little line scrubbing
      yaml_chunk += line
    end
  end
  # process last chunk, if it exists
  # process a yaml_chunk if we have one
  if !yaml_chunk.empty?
    data_hash = YAML.load(yaml_chunk)
    # insert data into database
    insert_to_db(run_date, suite, test_group, data_hash)
  end

end

optparse = options_parser
optparse.parse(ARGV)
if @options[:help]
  puts optparse.help
  exit
end
puts "Going to start processing!"
open_db(@options[:db])
if @options[:file]
  process_file(@options[:file])
elsif @options[:dir]
  # do the globbing
  files = Dir.glob(File.join(@options[:dir], "*"))
  files.each do |f|
    process_file(f)
  end
else
  puts "No file or directory to process"
end
@db.close
