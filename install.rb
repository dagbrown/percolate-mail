#!/usr/bin/ruby -w

require "rbconfig"
require "ftools"

module Percolate
    Package = "percolate-mail"

    class Install
        def self.mkdir(d)
            print "Creating #{d}..."
            begin
                Dir.mkdir(d)
                print "\n"
            rescue Errno::EEXIST
                if FileTest.directory? d
                    puts "no need, it's already there."
                else
                    puts "there's something else there already."
                    raise
                end
            rescue Errno::ENOENT
                puts "its parent doesn't exist!"
                raise
            end
        end

        def self.install(prefix=nil)
            include Config

            if prefix then
                dest   = File.join prefix, "lib"
                mkdir dest
            else
                version = CONFIG["MAJOR"] + "." + CONFIG["MINOR"]
                sitedir = CONFIG["sitedir"]
                dest    = File.join(sitedir,version)
            end

            destper = File.join(dest,"percolate")

            print "Installing #{Package}.rb in #{dest}...\n"
            File.install(File.join("lib","#{Package}.rb"), dest, 0644)
            
            mkdir destper
            Dir.glob(File.join("lib","percolate","*.rb")).each { |f|
                puts "Installing #{f} in #{destper}..."
                File.install(f,destper)
            }
        end
    end
end

if __FILE__ == $0 then
    Percolate::Install.install()
end
