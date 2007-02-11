# Please note that this is broken right now
#
# Yes, fixing it is on my TODO list.
#
# --Dave
require "test/unit"

$:.unshift File.join(File.dirname(__FILE__),"..","lib")

$DEBUG = ARGV.include? '-d'

require "percolate-mail"

class SMTPConnection
	def initialize
		@socket = TCPSocket.new "localhost", 10025
	end

	def response
		resp = ""
		str = @socket.recv(1000)
		resp << str
		$stderr.puts "<- #{resp.inspect}" if $DEBUG
		if resp.chomp("\r\n") == resp
			raise "whoops, we're not doing EOLs properly"
		else
			return resp.chomp("\r\n")
		end
	end

	def command str
		$stderr.puts "-> #{str.inspect}" if $DEBUG
		@socket.write_nonblock str + "\r\n"
	end
end

class TestPercolateResponder < Test::Unit::TestCase
	TestHostName="testhelohost"

	def setup
		@pid = fork do 
			listener = Percolate::Listener.new :hostname => TestHostName
			listener.go
		end

		sleep 0.2 # to give the listener time to fire up

		@responder ||= SMTPConnection.new
		# @responder = Percolate::Responder.new TestHostName, :debug => false
	end

	def teardown
		if @responder
			@responder.command 'quit'
			@responder.response
		end
		$stderr.puts "== killing #{@pid}" if $DEBUG
		Process.kill 'KILL', @pid
		$stderr.puts "== waiting for #{@pid}" if $DEBUG
		Process.waitpid @pid
		sleep 0.1
	end

	def test_initialize
		assert_equal "220 Ok", @responder.response
	end

	def test_helo
		test_initialize
		@responder.command "helo testhelohost"
		assert_equal "250 #{TestHostName}", @responder.response
	end

	def test_ehlo
		test_initialize
		@responder.command "ehlo testhelohost"
		assert_equal "250 #{TestHostName}", @responder.response
	end

	def test_randomcrap
		test_initialize
		@responder.command "huaglhuaglhuaglhuagl"
		assert_equal "500 command not recognized", @responder.response
	end

	def test_mail_from_valid
		test_ehlo
		@responder.command "mail from:<validaddress>"
		assert_equal "250 ok", @responder.response
	end

	def test_mail_from_nested
		test_mail_from_valid
		@responder.command "mail from:<anotheraddress>"
		assert_equal "503 Can't say MAIL right now", @responder.response
	end

	def test_mail_from_invalid
		test_ehlo
		@responder.command "mail from: invalidsyntax"
		assert_equal "501 bad MAIL FROM: parameter", @responder.response
		assert_nil @responder.instance_variable_get("@mail_object")
	end

	def test_good_after_bad
		test_mail_from_invalid
		@responder.command "mail from:<validaddress>"
		assert_equal "250 ok", @responder.response
		assert_not_nil @responder.instance_variable_get("@mail_object")
	end

	def test_rset_after_mail_from
		test_mail_from_valid
		@responder.command "rset"
		assert_equal "250 Ok", @responder.response
		assert_nil @smtpd.instance_variable_get("@mail_object")
		@responder.command "helo testhelohost"
		assert_equal "250 #{TestHostName}", @responder.response
		@responder.command "mail from:<anotheraddress>"
		assert_equal "250 ok", @responder.response
	end

	def test_rcpt_to_valid
		test_mail_from_valid
		@responder.command "rcpt to:<validrcptaddress>"
		assert_equal "250 ok", @responder.response
		assert_equal [ "validrcptaddress" ], 
			@responder.instance_variable_get("@mail_object") .
				envelope_to
	end

	def test_crappy_transaction_bad_from_good_to
		test_mail_from_invalid
		@responder.command "rcpt to:<validrcptaddress>"
		assert_equal "503 need MAIL FROM: first", 
			@responder.response
		assert_nil @responder.instance_variable_get("@mail_object") 
	end

	def test_rcpt_to_multiple
		test_rcpt_to_valid
		@responder.command "rcpt to:<anothervalidrcptaddress>"
		assert_equal "250 ok", @responder.response
		assert_equal [ "validrcptaddress", "anothervalidrcptaddress" ], 
			@responder.instance_variable_get("@mail_object") .
				envelope_to
	end

	def test_rcpt_to_invalid
		test_mail_from_valid
		@responder.command "rcpt to: not actually valid"
		assert_equal "501 bad RCPT TO: parameter", @responder.response
		assert_nil @responder.instance_variable_get("@mail_object") .
				envelope_to
	end

	def test_rcpt_to_at_wrong_time
		test_helo
		@responder.command "rcpt to:<validrcptaddress>"
		assert_equal "503 need MAIL FROM: first", @responder.response
	end

	def test_data
		test_rcpt_to_valid
		@responder.command "data"
		assert_equal "354 end data with <cr><lf>.<cr><lf>", 
			@responder.response
		@responder.command "This is a test"
		assert_equal nil, @responder.response
		@responder.command "Line 2 of the test"
		assert_equal nil, @responder.response
		@responder.command "."
		assert_equal "250 ok", @responder.response
	end

	def test_data_at_wrong_time
		test_mail_from_valid
		@responder.command "data"
		assert_equal "503 Specify sender and recipient first",
			@responder.response
	end

	def test_quit
		assert_raises Percolate::TransactionFinishedException do
			@responder.command "quit"
		end
		assert_equal "221 Pleasure doing business with you", 
					 @responder.response
	end

	def test_quit_after_message
		test_data
		test_quit
	end

	def test_quit_after_helo
		test_helo
		test_quit
	end

	def test_quit_after_mail_from
		test_mail_from_valid
		test_quit
	end

	def test_more_than_one_message
		test_data
		@responder.command "mail from:<validaddress>"
		assert_equal "250 ok", @responder.response
		assert_not_nil @responder.instance_variable_get("@mail_object")
		@responder.command "rcpt to:<validrcptaddress>"
		assert_equal "250 ok", @responder.response
		assert_equal [ "validrcptaddress" ], 
			@responder.instance_variable_get("@mail_object") .
				envelope_to
		@responder.command "data"
		assert_equal "354 end data with <cr><lf>.<cr><lf>", 
			@responder.response
		@responder.command "This is a test"
		assert_equal nil, @responder.response
		@responder.command "Line 2 of the test"
		assert_equal nil, @responder.response
		@responder.command "."
		assert_equal "250 ok", @responder.response
	end

	def test_long_complete_transaction
		test_more_than_one_message
	end
end
