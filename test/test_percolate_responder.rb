require "test/unit"

$:.unshift File.join(File.dirname(__FILE__),"..","lib")

require "percolate/responder"

class MyResponder < Percolate::Responder
    attr_writer :sender_validation, :recipient_validation

    Responses = { false => "no", true => "ok" }

    def initialize(hostname,opts={})
        @sender_validation = true
        @recipient_validation = true
        super(hostname, opts)
    end

    def validate_sender addr
        return @sender_validation, Responses[@sender_validation]
    end

    def validate_recipient addr
        return @recipient_validation, Responses[@recipient_validation]
    end
end

class TestPercolateResponder < Test::Unit::TestCase
    TestHostName="testhost"

    def setup
        @responder = Percolate::Responder.new TestHostName, :debug => false
    end

    def test_initialize
        assert_equal "220 Ok", @responder.response
    end

    def test_should_never_get_here
        # deliberately meddle about with the internal state of the thing
        # because I have no doubt that someone will at some point do just
        # that.
        @responder.instance_variable_set "@current_state", :data
        assert_raises Percolate::ResponderError do
            @responder.__send__ :connect
            puts @responder.response
        end
    end

    def test_helo
        test_initialize
        @responder.command "helo testhelohost"
        assert_equal "250 #{TestHostName}", @responder.response
        assert_equal "testhelohost", 
            @responder.instance_variable_get("@heloname")
    end

    def test_should_never_get_here
        test_helo
        assert_raises Percolate::ResponderError do
            @responder.__send__ "connect"
        end
    end

    def test_ehlo
        test_initialize
        @responder.command "ehlo testhelohost"
        assert_equal "250 #{TestHostName}", @responder.response
        assert_equal "testhelohost", 
            @responder.instance_variable_get("@heloname")
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
        assert_not_nil @responder.instance_variable_get("@mail_object")
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
        assert_equal "testhelohost", 
            @responder.instance_variable_get("@heloname")
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
        assert_match /^250 accepted, SMTP id is [0-9A-F]{16}$/, @responder.response
        assert_equal "This is a test\r\nLine 2 of the test\r\n", 
            @responder.instance_variable_get("@mail_object").content
    end

    def test_data_with_dot_on_line
        test_rcpt_to_valid
        @responder.command "data"
        assert_equal "354 end data with <cr><lf>.<cr><lf>", 
            @responder.response
        @responder.command ".."
        assert_equal nil, @responder.response
        @responder.command "."
        assert_match /^250 accepted, SMTP id is [0-9A-F]{16}$/, @responder.response
        assert_equal ".\r\n", 
            @responder.instance_variable_get("@mail_object").content
    end

    def test_data_at_wrong_time
        test_mail_from_valid
        @responder.command "data"
        assert_equal "503 Specify sender and recipient first",
            @responder.response
    end

    def quit
        assert_raises Percolate::TransactionFinishedException, 
            "This should never happen" do
            @responder.command "quit"
        end
        assert_equal "221 Pleasure doing business with you", 
                     @responder.response
    end

    def test_quit_after_message
        test_data
        quit
    end

    def test_quit_after_helo
        test_helo
        quit
    end

    def test_quit_after_mail_from
        test_mail_from_valid
        quit
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
        assert_match /^250 accepted, SMTP id is [0-9A-F]{16}$/, @responder.response
    end

    def test_long_complete_transaction
        test_more_than_one_message
        quit
    end
end

class TestSubclassedSMTPResponder < TestPercolateResponder
    def setup
        @responder = MyResponder.new TestHostName, :debug => false
    end

    def test_invalid_sender
        @responder.sender_validation = false

        test_ehlo
        @responder.command "mail from:<invalidaddress>"
        assert_equal "551 no", @responder.response
        assert_nil @responder.instance_variable_get("@mail_object")
        assert_nil @responder.sender
    end

    def test_valid_sender_after_invalid_sender
        test_invalid_sender

        @responder.sender_validation = true

        @responder.command "mail from:<validaddress>"
        assert_equal "250 ok", @responder.response
        assert_not_nil @responder.instance_variable_get("@mail_object")
        assert_not_nil @responder.sender
        assert_equal "validaddress", @responder.sender
    end

    def test_invalid_recipient
        @responder.recipient_validation = false

        test_mail_from_valid

        @responder.command "rcpt to:<invalidrcptaddress>"
        assert_equal "551 no", @responder.response
        assert_equal [ ], 
            @responder.instance_variable_get("@mail_object") .
                envelope_to
    end

    def test_valid_recipient_after_invalid
        test_invalid_recipient

        @responder.recipient_validation = true

        @responder.command "rcpt to:<validaddress>"
        assert_equal "250 ok", @responder.response
        assert_equal [ "validaddress" ],
            @responder.instance_variable_get("@mail_object") .
                envelope_to
    end
end

class TestDebug < TestPercolateResponder
    def setup
        @old_stderr = $stderr
        $stderr = File.open("/dev/null","w")
        @responder = Percolate::Responder.new TestHostName, :debug => true
    end
    
    def teardown
        $stderr = @old_stderr
    end
end
