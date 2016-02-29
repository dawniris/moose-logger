#!/usr/bin/env bundle exec ruby
require 'optparse'
require 'yaml'

DEFAULT_OPTIONS={
  :help  => false,
  :file  => nil,
}
@options=DEFAULT_OPTIONS
@db=nil

# Returns options parser object
def options_parser
  optparse = OptionParser.new do|opts|
    # Set a banner
    opts.banner = "Usage: #{File.basename($0)} [options...]"

    opts.on '-f', '--file FILE',
            'single file to process' do |filename|
      @options[:file] = filename
    end

    opts.on '-h', '--help' do
      @options[:help] = true
    end
  end
  optparse
end

def process_file(f)
  puts "FILE: \"#{f}\""

  suite = nil
  test_group = nil
  data_hash = {}
  yaml_chunk = ""
  full_hash =  {}
  # pull the run date out of the file name
  m = /^.*(\d\d\d\d-\d\d-\d\d).*(\d\d:\d\d)$/.match(f)
  run_date = "#{m[1]} #{m[2]}:00"
  File.foreach( f ) do |line|
    # garbage line, throw it away
    if line =~ /^(=======================)|(---)|(--- {})|(\.\.\.)$/
      puts "REJECTING: #{line}"
      next
    end
    if line =~ /(snapshots.zip)|(Scan and download)|(Automoose)|(Renew Financial Mail)|(^TOTAL )|(^SLOWEST GROUP)/
      puts "REJECTING: #{line}"
      next
    end
    if line =~ /^$/
      next
    end
    # find a header
    m = /^(\w*) - (\w*)$/.match(line)
    if !m.nil?
      # process a yaml_chunk if we have one
      data_hash = {}
      if !yaml_chunk.empty?
        begin
          data_hash = YAML.load(yaml_chunk)
        rescue => e
          puts "Failed to convert yaml string to hash"
          puts yaml_chunk
          raise e
        end
        full_hash[suite] ||= {}
        full_hash[suite] = full_hash[suite].merge(data_hash)
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
    puts "last chunk is \"#{yaml_chunk}\""
    data_hash = YAML.load(yaml_chunk)
    full_hash[suite] ||= {}
    full_hash[suite] = full_hash[suite].merge(data_hash)
  end
  # skim out anything that's not a FAIL
  fail_hash = {}
  full_hash.each_key do |suite|
    full_hash[suite].each_key do |test_group|
      full_hash[suite][test_group].each_key do |test_name|
        if full_hash[suite][test_group][test_name][:status] == "FAIL"
          puts "ADDING - failed test #{suite} - #{test_group} - #{test_name}"
          fail_hash[suite] ||= {}
          fail_hash[suite][test_group] ||= {}
          fail_hash[suite][test_group][test_name] = full_hash[suite][test_group][test_name]
        end
      end
    end
  end
  #print out
  fail_hash.each_key do |suite|
    puts "\noutput to file:  \"#{f}_#{suite}_failures.yml\""
    File.open("#{f}_#{suite}_failures.yml", 'w') do |f|
      f.puts fail_hash[suite].to_yaml
    end
  end
end

optparse = options_parser
optparse.parse(ARGV)
if @options[:help]
  puts optparse.help
  exit
end
puts "Going to start processing!"
if @options[:file]
  process_file(@options[:file])
else
  puts "No file to process"
end
