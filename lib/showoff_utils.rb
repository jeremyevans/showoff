class ShowOffUtils
  # Helper method to parse a comma separated options string and stores
  # the result in a dictionrary
  #
  # Example:
  #
  #    "tpl=hpi,title=Over the rainbow"
  #
  #    will be stored as
  #
  #      { "tpl" => "hpi", "title" => "Over the rainbow" }
  def self.parse_options(option_string="")
    result = {}

    if option_string
      option_string.split(",").each do |element|
        pair = element.split("=")
        result[pair[0]] = pair.size > 1 ? pair[1] : nil
      end
    end

    result
  end

  def self.presentation_config_file
    @presentation_config_file ||= 'showoff.json'
  end

  def self.presentation_config_file=(filename)
    @presentation_config_file = filename
  end

  def self.create(dirname,create_samples=false,dir='one')
    Dir.mkdir(dirname) if !File.exists?(dirname)
    Dir.chdir(dirname) do
      if create_samples
        # create section
        Dir.mkdir(dir)

        # create markdown file
        File.open("#{dir}/01_slide.md", 'w+') do |f|
          f.puts make_slide("My Presentation")
          f.puts make_slide("Bullet Points","bullets incremental",["first point","second point","third point"])
        end
      end

      # create showoff.json
      File.open(ShowOffUtils.presentation_config_file, 'w+') do |f|
        f.puts "{ \"name\": \"My Preso\", \"sections\": [ {\"section\":\"#{dir}\"} ]}"
      end
    end
  end

  def self.blank?(string)
    string.nil? || string.strip.length == 0
  end

  def self.determine_size_and_source(code)
    size = ""
    source = ""
    if code
      source,lines,width = read_code(code)
      size = adjust_size(lines,width)
    end
    [size,source]
  end

  def self.write_file(filename,slide)
    File.open(filename,'w') do |file|
      file.puts slide
    end
    puts "Wrote #{filename}"
  end

  def self.determine_filename(slide_dir,slide_name,number)
    filename = "#{slide_dir}/#{slide_name}.md"
    if number
      max = find_next_number(slide_dir)
      filename = "#{slide_dir}/#{max}_#{slide_name}.md"
    end
    filename
  end

  # Finds the next number in the given dir to
  # name a slide as the last slide in the dir.
  def self.find_next_number(slide_dir)
    max = 0
    Dir.open(slide_dir).each do |file|
      if file =~ /(\d+).*\.md/
        num = $1.to_i
        max = num if num > max
      end
    end
    max += 1
    max = "0#{max}" if max < 10
    max
  end

  def self.determine_title(title,slide_name,code)
    if blank?(title)
      title = slide_name
      title = File.basename(code) if code
    end
    title = "Title here" if blank?(title)
    title
  end

  # Determines a more optimal value for the size (e.g. small vs. smaller)
  # based upon the size of the code being formatted.
  def self.adjust_size(lines,width)
    size = ""
    # These values determined empircally
    size = "small" if width > 50
    size = "small" if lines > 15
    size = "smaller" if width > 57
    size = "smaller" if lines > 19
    puts "warning, some lines are too long and the code may be cut off" if width > 65
    puts "warning, your code is too long and the code may be cut off" if lines > 23
    size
  end

  # Reads the code from the source file, returning
  # the code, indented for markdown, as well as the number of lines
  # and the width of the largest line
  def self.read_code(source_file)
    code = "    @@@ #{lang(source_file)}\n"
    lines = 0
    width = 0
    File.open(source_file) do |code_file|
      code_file.readlines.each do |line|
        code += "    #{line}"
        lines += 1
        width = line.length if line.length > width
      end
    end
    [code,lines,width]
  end

  def self.showoff_sections(dir,logger)
    index = File.join(dir, ShowOffUtils.presentation_config_file)
    sections = nil
    if File.exists?(index)
      data = JSON.parse(File.read(index))
      logger.debug data
      if data.is_a?(Hash)
        sections = data['sections']
      else
        sections = data
      end
      sections = sections.map do |s|
        if s.is_a? Hash
          s['section']
        else
          s
        end
      end
    else
      sections = ["."] # if there's no showoff.json file, make a boring one
    end
    sections
  end

  def self.showoff_title(dir = '.')
    get_config_option(dir, 'name', "Presentation")
  end

  def self.pause_msg(dir = '.')
    get_config_option(dir, 'pause_msg', 'PAUSED')
  end

  def self.default_style(dir = '.')
    get_config_option(dir, 'style', '')
  end

  def self.default_style?(style, dir = '.')
    default = default_style(dir)
    style.split('/').last.sub(/\.css$/, '') == default
  end

  def self.get_config_option(dir, option, default = nil)
    index = File.join(dir, ShowOffUtils.presentation_config_file)
    if File.exists?(index)
      data = JSON.parse(File.read(index))
      if data.is_a?(Hash)
        if default.is_a?(Hash)
          default.merge(data[option] || {})
        else
          data[option] || default
        end
      end
    else
      default
    end
  end

  EXTENSIONS =  {
    'pl' => 'perl',
    'rb' => 'ruby',
    'erl' => 'erlang',
    # so not exhaustive, but probably good enough for now
  }

  def self.lang(source_file)
    ext = File.extname(source_file).gsub(/^\./,'')
    EXTENSIONS[ext] || ext
  end
end
