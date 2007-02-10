require 'rake/gempackagetask'

PKG_VERSION = "1.0.0"
PKG_NAME = "percolate-mail"
PKG_FILE_NAME = "#{PKG_NAME}-#{PKG_VERSION}"

spec = Gem::Specification.new do |s|
    s.name = PKG_NAME
    s.version = PKG_VERSION
    s.required_ruby_version = ">= 1.8.4"
    s.summary = "Skeleton smtp daemon for you to subclass"
    # s.description = "FIXME"
    s.has_rdoc = true

    s.files = Dir['lib/**/*'] + Dir['test/**/*']
    
    s.require_path = 'lib'
    s.author = "Dave Brown"
    s.email = "dagbrown@lart.ca"
    s.homepage = "http://percolate-mail.rubyforge.org/"
    s.rubyforge_project = "percolate-mail"
    s.platform = Gem::Platform::RUBY 
end

Rake::GemPackageTask.new(spec) do |p|
    p.gem_spec = spec
    p.need_tar = true
    p.need_zip = false
end
