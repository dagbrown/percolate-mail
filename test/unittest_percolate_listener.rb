
require "test/unit"

$: << File.join(File.dirname(__FILE__),"..","lib")
require "percolate-mail"

class Responder
    def command cmd
        nil
    end

    def response
        "Boxcar!"
    end
end

class SMTPConnection
    def initialize
        @socket = TCPSocket.new "localhost", 10025
    end

    def response
        resp = ""
        begin
            str = @socket.recv_nonblock(1000)
            resp << str
        rescue Errno::EAGAIN
            if resp.chomp "\r\n" == resp
                raise Error, "whoops, we're not doing EOLs properly"
            else
                return resp
            end
        end
    end

    def send str
        @socket.write_nonblock str + "\r\n"
    end
end


class TestPercolateListener < Test::Unit::TestCase
    TestHostName="localhost"

    def test_startup_and_shutdown
        listener = Percolate::Listener.new :hostname => TestHostName,
            :responder => ::Responder, :port => 10025
        pid = fork do
            listener.go
        end

        sleep 0.1

        sock = nil

        assert_nothing_raised do
            sock = TCPSocket.new "localhost", 10025
        end

        assert_nothing_raised do
            sock.write "\r\n"
        end

        assert_raises Errno::EAGAIN do
            assert_equal "Boxcar!\r\n", sock.recv_nonblock(1000)
        end

        sock.close

        Process.kill 'INT', pid

        sleep 0.1

        assert_raises Errno::ECONNREFUSED do
            TCPSocket.new "localhost", 10025
        end
    end
end
