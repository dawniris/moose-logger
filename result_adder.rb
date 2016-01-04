require 'optparse'
require 'yaml'

DEFAULT_OPTIONS={
  :help  => false,
  :file  => nil,
  :dir   => nil,
}
@options=DEFAULT_OPTIONS

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

    opts.on '-h', '--help' do
      @options[:help] = true
    end
  end
  optparse
end

def process_file(f)
  puts "processing file: \"#{f}\""

  suite = nil
  test_group = nil
  yaml_chunk = ""
  File.foreach( f ) do |line|
    # nothing line, throw it away
    if line =~ /^(=======================)|(---)|(--- {})|(%.*%)$/
      next
    end
    # find a header
    m = /^(\w*) - (\w*)$/.match(line)
    if !m.nil?
      # process a yaml_chunk if we have one
      if !yaml_chunk.empty?
        data = YAML.load(yaml_chunk)
        # insert data into database
        puts data.inspect
      end
      # get the new data and start over
      yaml_chunk = ""
      suite = m[1]
      test_group = m[2]
      puts "aw yiss #{suite} - #{test_group}"
    else
      yaml_chunk += line
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
elsif @options[:dir]
  # do the globbing
  files = Dir.glob(File.join(@options[:dir], "*"))
  files.each do |f|
    process_file(f)
  end
else
  puts "No file or directory to process"
end
