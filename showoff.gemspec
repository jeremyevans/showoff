Gem::Specification.new do |s|
  s.name              = "jeremyevans-showoff"
  s.version           = '1.0.7'
  s.summary           = "The best damn presentation software a developer could ever love."
  s.homepage          = "https://github.com/jeremyevans/showoff"
  s.email             = "code@jeremyevans.net"
  s.authors           = ["Scott Chacon", "Jeremy Evans"]
  s.require_path      = "lib"
  s.executables       = %w( showoff )
  s.licenses          = %w'MIT'
  s.files             = %w( README.rdoc Rakefile LICENSE )
  s.files            += Dir.glob("lib/**/*")
  s.files            += Dir.glob("bin/**/*")
  s.files            += Dir.glob("views/**/*")
  s.files            += Dir.glob("public/**/*")
  s.add_dependency      "roda", ">= 3.13"
  s.add_dependency      "tilt", ">= 2.2"
  s.add_dependency      "json"
  s.add_dependency      "kramdown"
  s.add_dependency      "nokogiri"
  s.add_dependency      "erubi"

  s.description       = <<-desc
My fork of showoff with a lot of features removed.
  desc
end
