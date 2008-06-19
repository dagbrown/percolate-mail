#!/usr/bin/ruby -w

require "rbconfig"
require "fileutils"
require "ftools"

module Percolate
    Package = "percolate-mail"

    class Install
        def self.install(prefix=nil, opts = {})
            include Config

            if opts[:destdir]
                destdir = opts[:destdir]
            else
                destdir = '/'
            end

            if prefix then
                dest   = File.join destdir, prefix, "lib"
            else
                version = CONFIG["MAJOR"] + "." + CONFIG["MINOR"]
                sitedir = CONFIG["sitedir"]
                dest    = File.join(destdir,sitedir,version)
            end

            FileUtils.mkdir_p dest

            destper = File.join(dest,"percolate")

            print "Installing #{Package}.rb in #{dest}...\n"
            File.install(File.join("lib","#{Package}.rb"), dest, 0644)
            
            FileUtils.mkdir_p destper
            Dir.glob(File.join("lib","percolate","*.rb")).each { |f|
                puts "Installing #{f} in #{destper}..."
                File.install(f,destper)
            }

            FileUtils.mkdir_p File.join(destper, "smtp");
            Dir.glob(File.join("lib", "percolate", "smtp", "*.rb")).each do |f|
                puts "Installing #{f} in #{destper}/smtp..."
                File.install(f,File.join(destper,"smtp"))
            end

        end
    end
end

if __FILE__ == $0 then
    $destdir = nil
    require 'optparse'
    opts = OptionParser.new do |o|
        o.on("--destdir DESTDIR", String, "Install into DESTDIR") do |p|
            $destdir = p
        end
    end
    opts.parse(ARGV)
    Percolate::Install.install(nil, :destdir => $destdir)
end
