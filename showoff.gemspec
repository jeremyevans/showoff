$:.unshift File.expand_path("../lib", __FILE__)
require 'showoff/version'
require 'date'

Gem::Specification.new do |s|
  s.name              = "jeremyevans-showoff"
  s.version           = SHOWOFF_VERSION
  s.date              = Date.today.to_s
  s.summary           = "The best damn presentation software a developer could ever love."
  s.homepage          = "https://github.com/jeremyevans/showoff"
  s.email             = "code@jeremyevans.net"
  s.authors           = ["Scott Chacon"]
  s.has_rdoc          = false
  s.require_path      = "lib"
  s.executables       = %w( showoff )
  s.files             = %w( README.rdoc Rakefile LICENSE )
  s.files            += Dir.glob("lib/**/*")
  s.files            += Dir.glob("bin/**/*")
  s.files            += Dir.glob("views/**/*")
  s.files            += Dir.glob("public/**/*")
  s.add_dependency      "sinatra", "~> 1.3"
  s.add_dependency      "json"
  s.add_dependency      "gli",">= 1.3.2"
  s.add_dependency      "parslet"
  s.add_dependency      "htmlentities"
  s.add_dependency      "maruku"
  
  # both gems fail to build on Ruby 1.8.7, the default in older OS X
  if RUBY_VERSION.to_f < 1.9
    s.add_dependency      "nokogiri",  "< 1.5.10"
  else
    s.add_dependency      "nokogiri"
  end

  s.add_development_dependency "mg"
  s.description       = <<-desc
My fork of showoff with a lot of features removed.
  desc
end
