require "rake"
require "ftools"
require "rake/classic_namespace"

Package = "percolate-mail"

Version = File.read("VERSION").chomp
Gemfile = "#{Package}-#{Version}.gem"
Gemspec = "#{Package}.gemspec"
Tarball = "#{Package}-#{Version}.tar.gz"

Files = [ "install.rb", "INSTALL" ] + Dir["lib/**/*.rb"]

task :dist => [ :test, :tarball, :gem ]

task :gem => Gemfile do File.move Gemfile,".." end
task :tarball => Tarball do File.move Tarball, ".." end

file Tarball => Files do
    run "tar","zcvf",Tarball,*Files
end

file Gemfile do
    run "gem build #{Gemspec}"
end

task :test do
    FileList['test/*.rb'].each do |f|
        run("ruby #{f}")
    end
end

def run(*cmd)
    puts cmd.join(" ")
    system(*cmd) or fail "Command failed: [#{cmd}]"
end
