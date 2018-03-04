require 'sinatra/base'
require 'json'
require 'nokogiri'
require 'fileutils'
require 'logger'
require 'maruku'

require_relative "showoff_utils"

require 'tilt'

class ShowOff < Sinatra::Application

  # Set up application variables

  set :views, File.dirname(__FILE__) + '/../views'
  set :public_folder, File.dirname(__FILE__) + '/../public'

  set :verbose, false
  set :pres_dir, '.'
  set :pres_file, 'showoff.json'
  set :page_size, "Letter"
  set :pres_template, nil
  set :showoff_config, {}
  set :encoding, nil

  @@downloads = Hash.new # Track downloadable files
  @@cookie    = nil      # presenter cookie. Identifies the presenter for control messages
  @@current   = Hash.new # The current slide that the presenter is viewing

  def initialize(app=nil)
    super(app)
    @logger = Logger.new(STDOUT)
    @logger.formatter = proc { |severity,datetime,progname,msg| "#{progname} #{msg}\n" }
    @logger.level = settings.verbose ? Logger::DEBUG : Logger::WARN

    dir = File.expand_path(File.join(File.dirname(__FILE__), '..'))
    @logger.debug(dir)

    showoff_dir = File.expand_path(File.join(File.dirname(__FILE__), '..'))
    settings.pres_dir ||= Dir.pwd
    @root_path = "."

    settings.pres_dir = File.expand_path(settings.pres_dir)
    if (settings.pres_file)
      ShowOffUtils.presentation_config_file = settings.pres_file
    end

    # Load configuration for page size and template from the
    # configuration JSON file
    if File.exists?(ShowOffUtils.presentation_config_file)
      showoff_json = JSON.parse(File.read(ShowOffUtils.presentation_config_file))
      settings.showoff_config = showoff_json

      # Set options for encoding, template and page size
      settings.encoding = showoff_json["encoding"]
      settings.page_size = showoff_json["page-size"] || "Letter"
      settings.pres_template = showoff_json["templates"]
    end

    @logger.debug settings.pres_template

    @logger.debug settings.pres_dir
    @pres_name = settings.pres_dir.split('/').pop
    require_ruby_files

    # Default asset path
    @asset_path = "./"

    Tilt.prefer Tilt::MarukuTemplate, "markdown"
  end

  def self.pres_dir_current
    opt = {:pres_dir => Dir.pwd}
    ShowOff.set opt
  end

  def require_ruby_files
    Dir.glob("#{settings.pres_dir}/*.rb").map { |path| require path }
  end

  helpers do
    def load_section_files(section)
      section = File.join(settings.pres_dir, section)
      files = if File.directory? section
        Dir.glob("#{section}/**/*").sort
      else
        [section]
      end
      @logger.debug files
      files
    end

    def css_files
      Dir.glob("#{settings.pres_dir}/*.css").map { |path| File.basename(path) }
    end

    def js_files
      Dir.glob("#{settings.pres_dir}/*.js").map { |path| File.basename(path) }
    end


    def preshow_files
      Dir.glob("#{settings.pres_dir}/_preshow/*").map { |path| File.basename(path) }.to_json
    end

    # todo: move more behavior into this class
    class Slide
      attr_reader :classes, :text, :tpl, :bg
      def initialize( context = "")

        @tpl = "default"
        @classes = []

        # Parse the context string for options and content classes
        if context and context.match(/(\[(.*?)\])?(.*)/)
          options = ShowOffUtils.parse_options($2)
          @tpl = options["tpl"] if options["tpl"]
          @bg = options["bg"] if options["bg"]
          @classes += $3.strip.chomp('>').split if $3
        end

        @text = ""
      end
      def <<(s)
        @text << s
        @text << "\n"
      end
      def empty?
        @text.strip == "" || @classes == ['skip']
      end
    end

    def process_markdown(name, content, opts={:static=>false, :print=>false, :toc=>false, :supplemental=>nil})
      if settings.encoding and content.respond_to?(:force_encoding)
        content.force_encoding(settings.encoding)
      end

      # if there are no !SLIDE markers, then make every H1 define a new slide
      unless content =~ /^\<?!SLIDE/m
        content = content.gsub(/^# /m, "<!SLIDE>\n# ")
      end

      # todo: unit test
      lines = content.split("\n")
      @logger.debug "#{name}: #{lines.length} lines"
      slides = []
      slides << (slide = Slide.new)
      until lines.empty?
        line = lines.shift
        if line =~ /^<?!SLIDE(.*)>?/
          ctx = $1 ? $1.strip : $1
          slides << (slide = Slide.new(ctx))
        else
          slide << line
        end
      end

      slides.delete_if {|slide| slide.empty? }

      final = ''
      if slides.size > 1
        seq = 1
      end
      slides.each do |slide|
        # update section counters before we reject slides so the numbering is consistent
        if slide.classes.include? 'subsection'
          @section_major += 1
          @section_minor = 0
        end

        if opts[:supplemental]
          # if we're looking for supplemental material, only include the content we want
          next unless slide.classes.include? 'supplemental'
          next unless slide.classes.include? opts[:supplemental]
        else
          # otherwise just skip all supplemental material completely
          next if slide.classes.include? 'supplemental'
        end

        unless opts[:toc]
          # just drop the slide if we're not generating a table of contents
          next if slide.classes.include? 'toc'
        end

        if opts[:print]
          # drop all slides not intended for the print version
          next if slide.classes.include? 'noprint'
        else
          # drop slides that are intended for the print version only
          next if slide.classes.include? 'printonly'
        end

        @slide_count += 1
        content_classes = slide.classes

        # extract transition, defaulting to none
        transition = 'none'
        content_classes.delete_if { |x| x =~ /^transition=(.+)/ && transition = $1 }
        # extract id, defaulting to none
        id = nil
        content_classes.delete_if { |x| x =~ /^#([\w-]+)/ && id = $1 }
        id = name unless id
        @logger.debug "id: #{id}" if id
        @logger.debug "classes: #{content_classes.inspect}"
        @logger.debug "transition: #{transition}"
        @logger.debug "tpl: #{slide.tpl} " if slide.tpl
        @logger.debug "bg: #{slide.bg}" if slide.bg


        template = "~~~CONTENT~~~"
        # Template handling
        if settings.pres_template
          # We allow specifying a new template even when default is
          # not given.
          if settings.pres_template.include?(slide.tpl) and
              File.exists?(settings.pres_template[slide.tpl])
            template = File.open(settings.pres_template[slide.tpl], "r").read()
          end
        end

        # create html for the slide
        classes = content_classes.join(' ')
        content = "<div"
        content += " id=\"#{id}\"" if id
        content += " style=\"background: url('file/#{slide.bg}') center no-repeat;\"" if slide.bg
        content += " class=\"slide #{classes}\" data-transition=\"#{transition}\">"

        # name the slide. If we've got multiple slides in this file, we'll have a sequence number
        # include that sequence number to index directly into that content
        if seq
          content += "<div class=\"content #{classes}\" ref=\"#{name}/#{seq.to_s}\">\n"
        else
          content += "<div class=\"content #{classes}\" ref=\"#{name}\">\n"
        end

        # Apply the template to the slide and replace the key to generate the content of the slide
        sl = template.gsub(/~~~CONTENT~~~/, slide.text)
        sl = Tilt[:markdown].new(nil, nil, {}) { sl }.render
        sl = update_p_classes(sl)
        sl = update_special_content(sl, @slide_count, name) # TODO: deprecated
        sl = update_image_paths(name, sl, opts)

        content += sl
        content += "</div>\n"
        content += "</div>\n"

        final += update_commandline_code(content)

        if seq
          seq += 1
        end
      end
      final
    end

    def process_content_for_all_slides(content, num_slides, opts={})
      content.gsub!("~~~NUM_SLIDES~~~", num_slides.to_s)

      # Should we build a table of contents?
      if opts[:toc]
        frag = Nokogiri::HTML::DocumentFragment.parse ""
        toc = Nokogiri::XML::Node.new('div', frag)
        toc['id'] = 'toc'
        frag.add_child(toc)

        Nokogiri::HTML(content).css('div.subsection > h1').each do |section|
          entry = Nokogiri::XML::Node.new('div', frag)
          entry['class'] = 'tocentry'
          toc.add_child(entry)

          link = Nokogiri::XML::Node.new('a', frag)
          link['href'] = "##{section.parent.parent['id']}"
          link.content = section.content
          entry.add_child(link)
        end

        # swap out the tag, if found, with the table of contents
        content.gsub!("~~~TOC~~~", frag.to_html)
      end

      content
    end

    # find any lines that start with a <p>.(something) and turn them into <p class="something">
    def update_p_classes(markdown)
      markdown.gsub(/<p>\.(.*?) /, '<p class="\1">')
    end

    # TODO: deprecated
    def update_special_content(content, seq, name)
      doc = Nokogiri::HTML::DocumentFragment.parse(content)
      %w[notes handouts instructor solguide].each { |mark|  update_special_content_mark(doc, mark) }
      update_download_links(doc, seq, name)

      # TODO: what the bloody hell. Figure out how to either make Nokogiri output closed
      # tags or figure out how to get its XML output to quit adding gratuitious spaces.
      doc.to_html.gsub(/(<img [^>]*)>/, '\1 />')
    end

    # TODO: deprecated
    def update_special_content_mark(doc, mark)
      container = doc.css("p.#{mark}").first
      return unless container

      # only allow localhost to print the instructor guide
      if mark == 'instructor' and request.env['REMOTE_HOST'] != 'localhost'
        container.remove
      else
        raw      = container.inner_html
        fixed    = raw.gsub(/^\.#{mark} ?/, '')
        markdown = Tilt[:markdown].new { fixed }.render

        container.name       = 'div'
        container.inner_html = markdown
      end
    end
    private :update_special_content_mark

    def update_download_links(doc, seq, name)
      container = doc.css("p.download").first
      return unless container

      raw      = container.text
      fixed    = raw.gsub(/^\.download ?/, '')

      # first create the data structure
      # [ enabled, slide name, [array, of, files] ]
      @@downloads[seq] = [ false, name, [] ]

      fixed.split("\n").each { |file|
        # then push each file onto the list
        @@downloads[seq][2].push(file.strip)
      }

      container.remove
    end
    private :update_download_links

    def update_image_paths(path, slide, opts={:static=>false})
      paths = path.split('/')
      paths.pop
      path = paths.join('/')
      replacement_prefix = opts[:static] ?  %(img src="./file/#{path}) : %(img src="#{@asset_path}image/#{path})
      slide.gsub(/img src=[\"\'](?!https?:\/\/)([^\/].*?)[\"\']/) do |s|
        img_path = File.join(path, $1)
        %(#{replacement_prefix}/#{$1}")
      end
    end

    def update_commandline_code(slide)
      html = Nokogiri::XML.parse(slide)

      html.css('pre').each do |pre|
        pre.css('code').each do |code|
          out = code.text
          lines = out.split("\n")
          if lines.first.strip[0, 3] == '@@@'
            lang = lines.shift.gsub('@@@', '').strip
            pre.set_attribute('class', 'sh_' + lang.downcase) if !lang.empty?
            code.content = lines.join("\n")
          end
        end
      end

      html.root.to_s
    end

    def get_slides_html(opts={:static=>false, :toc=>false, :supplemental=>nil})
      @slide_count   = 0
      @section_major = 0
      @section_minor = 0

      sections = ShowOffUtils.showoff_sections(settings.pres_dir, @logger)
      files = []
      if sections
        data = ''
        sections.each do |section|
          if section =~ /^#/
            name = section.each_line.first.gsub(/^#*/,'').strip
            data << process_markdown(name, "<!SLIDE subsection>\n" + section, opts)
          else
            files = []
            files << load_section_files(section)
            files = files.flatten
            files = files.select { |f| f =~ /.md$/ }
            files.each do |f|
              fname = f.gsub(settings.pres_dir + '/', '').gsub('.md', '')
              data << process_markdown(fname, File.read(f), opts)
            end
          end
        end
      end
      process_content_for_all_slides(data, @slide_count, opts)
    end

    def inline_css(csses, pre = nil)
      css_content = '<style type="text/css">'
      csses.each do |css_file|
        if pre
          css_file = File.join(File.dirname(__FILE__), '..', pre, css_file)
        else
          css_file = File.join(settings.pres_dir, css_file)
        end
        css_content += File.read(css_file)
      end
      css_content += '</style>'
      css_content
    end

    def inline_js(jses, pre = nil)
      js_content = '<script type="text/javascript">'
      jses.each do |js_file|
        if pre
          js_file = File.join(File.dirname(__FILE__), '..', pre, js_file)
        else
          js_file = File.join(settings.pres_dir, js_file)
        end

        begin
          js_content += File.read(js_file)
        rescue Errno::ENOENT
          $stderr.puts "WARN: Failed to inline JS. No such file: #{js_file}"
          next
        end
      end
      js_content += '</script>'
      js_content
    end

    def inline_all_js(jses_directory)
       inline_js(Dir.entries(File.join(File.dirname(__FILE__), '..', jses_directory)).find_all{|filename| filename.length > 2 }, jses_directory)
    end

    def index(static=false)
      if static
        @static = true
        @title = ShowOffUtils.showoff_title(settings.pres_dir)
        @slides = get_slides_html(:static=>static)
        @pause_msg = ShowOffUtils.pause_msg

        # Identify which languages to bundle for highlighting
        @languages = @slides.scan(/<pre class=".*(?!sh_sourceCode)(sh_[\w-]+).*"/).uniq.map{ |w| "sh_lang/#{w[0]}.min.js"}

        @asset_path = "./"
      end

      erb :index
    end

    def presenter(static=false)
      if static
        @title = ShowOffUtils.showoff_title(settings.pres_dir)
        @slides = get_slides_html(:static=>static)
        @pause_msg = ShowOffUtils.pause_msg

        # Identify which languages to bundle for highlighting
        @languages = @slides.scan(/<pre class=".*(?!sh_sourceCode)(sh_[\w-]+).*"/).uniq.map{ |w| "sh_lang/#{w[0]}.min.js"}

        @asset_path = "./"
      else
        @@cookie ||= guid()
        response.set_cookie('presenter', @@cookie)
      end

      erb :presenter
    end

    def clean_link(href)
      if href && href[0, 1] == '/'
        href = href[1, href.size]
      end
      href
    end

    def assets_needed
      assets = ["index", "slides"]

      index = erb :index
      html = Nokogiri::XML.parse(index)
      html.css('head link').each do |link|
        href = clean_link(link['href'])
        assets << href if href
      end
      html.css('head script').each do |link|
        href = clean_link(link['src'])
        assets << href if href
      end

      slides = get_slides_html
      html = Nokogiri::XML.parse("<slides>" + slides + "</slides>")
      html.css('img').each do |link|
        href = clean_link(link['src'])
        assets << href if href
      end

      css = Dir.glob("#{settings.public_folder}/**/*.css").map { |path| path.gsub(settings.public_folder + '/', '') }
      assets << css

      js = Dir.glob("#{settings.public_folder}/**/*.js").map { |path| path.gsub(settings.public_folder + '/', '') }
      assets << js

      assets.uniq.join("\n")
    end

    def slides(static=false)
      get_slides_html(:static=>static)
    end

    def onepage(static=false)
      @slides = get_slides_html(:static=>static, :toc=>true)
      #@languages = @slides.scan(/<pre class=".*(?!sh_sourceCode)(sh_[\w-]+).*"/).uniq.map{ |w| "/sh_lang/#{w[0]}.min.js"}
      erb :onepage
    end

    def print(static=false)
      @slides = get_slides_html(:static=>static, :toc=>true, :print=>true)
      erb :onepage
    end

    def supplemental(content, static=false)
      @slides = get_slides_html(:static=>static, :supplemental=>content)
      @wrapper_classes = ['supplemental']
      erb :onepage
    end

    def download()
      begin
        shared = Dir.glob("#{settings.pres_dir}/_files/share/*").map { |path| File.basename(path) }
        # We use the icky -999 magic index because it has to be comparable for the view sort
        @downloads = { -999 => [ true, 'Shared Files', shared ] }
      rescue Errno::ENOENT => e
        # don't fail if the directory doesn't exist
        @downloads = {}
      end
      @downloads.merge! @@downloads
      erb :download
    end
  end


   def self.do_static(what)
      what = "index" if !what

      # Sinatra now aliases new to new!
      # https://github.com/sinatra/sinatra/blob/v1.3.3/lib/sinatra/base.rb#L1369
      showoff = ShowOff.new!

      name = showoff.instance_variable_get(:@pres_name)
      path = showoff.instance_variable_get(:@root_path)
      logger = showoff.instance_variable_get(:@logger)

      data = showoff.send(what, true)

      out = File.expand_path("#{path}/static")
      # First make a directory
      FileUtils.makedirs(out)
      # Then write the html
      file = File.new("#{out}/index.html", "w")
      file.puts(data)
      file.close
      if what == 'index'
        data = showoff.presenter(true)
        file = File.new("#{out}/presenter.html", "w")
        file.puts(data)
        file.close
      end
      # Now copy all the js and css
      my_path = File.join( File.dirname(__FILE__), '..', 'public')
      ["js", "css"].each { |dir|
        FileUtils.copy_entry("#{my_path}/#{dir}", "#{out}/#{dir}")
      }
      # And copy the directory
      Dir.glob("#{my_path}/#{name}/*").each { |subpath|
        base = File.basename(subpath)
        next if "static" == base
        next unless File.directory?(subpath) || base.match(/\.(css|js)$/)
        FileUtils.copy_entry(subpath, "#{out}/#{base}")
      }

      # Set up file dir
      file_dir = File.join(out, 'file')
      FileUtils.makedirs(file_dir)
      pres_dir = showoff.settings.pres_dir

      # ..., copy all user-defined styles, javascript, images, and fonts
      Dir.glob("#{pres_dir}/*.{css,js,png,jpg,svg,gif,ttf}").each { |path|
        FileUtils.copy(path, File.join(file_dir, File.basename(path)))
      }

      # ... and copy all needed image files
      [/img src=[\"\'].\/file\/(.*?)[\"\']/, /style=[\"\']background: url\(\'file\/(.*?)'/].each do |regex|
        data.scan(regex).flatten.each do |path|
          path = path.gsub('../file/', '')
          dir = File.dirname(path)
          FileUtils.makedirs(File.join(file_dir, dir))
          FileUtils.copy(File.join(pres_dir, path), File.join(file_dir, path))
        end
      end
      # copy images from css too
      Dir.glob("#{pres_dir}/*.css").each do |css_path|
        File.open(css_path) do |file|
          data = file.read
          data.scan(/url\([\"\']?(?!https?:\/\/)(.*?)[\"\']?\)/).flatten.each do |path|
            path.gsub!(/(\#.*)$/, '') # get rid of the anchor
            path.gsub!(/(\?.*)$/, '') # get rid of the query
            logger.debug path
            dir = File.dirname(path)
            FileUtils.makedirs(File.join(file_dir, dir))
            FileUtils.copy(File.join(pres_dir, path), File.join(file_dir, path))
          end
        end
      end
    end

   def eval_ruby code
     eval(code).to_s
   rescue => e
     e.message
   end

  # Basic auth boilerplate
  def protected!
    unless authorized?
      response['WWW-Authenticate'] = %(Basic realm="#{@title}: Protected Area")
      throw(:halt, [401, "Not authorized\n"])
    end
  end

  def authorized?
    if not settings.showoff_config.has_key? 'password'
      # if no password is set, then default to allowing access to localhost
      request.env['REMOTE_HOST'] == 'localhost' or request.ip == '127.0.0.1'
    else
      auth   ||= Rack::Auth::Basic::Request.new(request.env)
      user     = settings.showoff_config['user'] || ''
      password = settings.showoff_config['password']
      auth.provided? && auth.basic? && auth.credentials && auth.credentials == [user, password]
    end
  end

  def guid
    # this is a terrifyingly simple GUID generator
    (0..15).to_a.map{|a| rand(16).to_s(16)}.join
  end

  def valid_cookie
    (request.cookies['presenter'] == @@cookie)
  end

  get '/eval_ruby' do
    return eval_ruby(params[:code]) if ENV['SHOWOFF_EVAL_RUBY']

    return "Ruby Evaluation is off. To turn it on set ENV['SHOWOFF_EVAL_RUBY']"
  end

  get %r{/(?:image|file)/(.*)} do
    path = params[:captures].first
    full_path = File.join(settings.pres_dir, path)
    if File.exist?(full_path)
        send_file full_path
    else
        raise Sinatra::NotFound
    end
  end

  # gawd, this whole routing scheme is bollocks
  get %r{/([^/]*)/?([^/]*)} do
    @title = ShowOffUtils.showoff_title(settings.pres_dir)
    @pause_msg = ShowOffUtils.pause_msg
    what = params[:captures].first
    opt  = params[:captures][1]
    what = 'index' if "" == what
    what.sub!(/\A(index|presenter)\.html\z/, '\1')

    if settings.showoff_config.has_key? 'protected'
      protected! if settings.showoff_config['protected'].include? what
    end

    # this hasn't been set to anything remotely interesting for a long time now
    @asset_path = nil

    begin
      if (what != "favicon.ico")
        if what == 'supplemental'
          data = send(what, opt)
        else
          data = send(what)
        end
        if data.is_a?(File)
          send_file data.path
        else
          data
        end
      end
    rescue NoMethodError => e
      @logger.warn "Invalid object #{what} requested. #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
      raise Sinatra::NotFound
    end
  end

  not_found do
    # Why does the asset path start from cwd??
    @asset_path.slice!(/^./) if @asset_path
    @env = request.env
    erb :'404'
  end
end
