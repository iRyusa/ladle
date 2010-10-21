require File.expand_path("../../spec_helper.rb", __FILE__)

require 'net/ldap'

describe Ladle, "::Server" do
  def create_server(opts = {})
    Ladle::Server.new({ :quiet => true }.merge(opts))
  end

  before do
    @server = create_server
  end

  after do
    @server.stop

    left_over_pids = `ps`.split("\n").grep(/net.detailedbalance.ladle.Main/).
      collect { |line| line.split(/\s+/)[0].to_i }
    left_over_pids.each { |pid|
      $stderr.puts "Killing leftover process #{pid}"
      Process.kill 15, pid
    }
    left_over_pids.should be_empty
  end

  describe "initialization of" do
    describe ":port" do
      it "defaults to 3897" do
        Ladle::Server.new.port.should == 3897
      end

      it "can be overridden" do
        Ladle::Server.new(:port => 4200).port.should == 4200
      end
    end

    describe ":domain" do
      it "defaults to dc=example,dc=org" do
        Ladle::Server.new.domain.should == "dc=example,dc=org"
      end

      it "can be overridden" do
        Ladle::Server.new(:domain => "dc=northwestern,dc=edu").domain.
          should == "dc=northwestern,dc=edu"
      end

      it "rejects a domain that doesn't start with 'dc='" do
        lambda { Ladle::Server.new(:domain => "foo") }.
          should raise_error("The domain component must start with 'dc='.  'foo' does not.")
      end
    end

    describe ":ldif" do
      it "defaults to lib/ladle/default.ldif" do
        Ladle::Server.new.ldif.should =~ %r{lib/ladle/default.ldif$}
      end

      it "can be overridden" do
        ldif_file = "#{tmpdir}/foo.ldif"
        FileUtils.touch ldif_file
        Ladle::Server.new(:ldif => ldif_file).ldif.should == ldif_file
      end

      it "fails if the file can't be read" do
        lambda { Ladle::Server.new(:ldif => "foo/bar.ldif") }.
          should raise_error("Cannot read specified LDIF file foo/bar.ldif.")
      end
    end

    describe ":verbose" do
      it "defaults to false" do
        Ladle::Server.new.verbose?.should be_false
      end

      it "can be overridden" do
        Ladle::Server.new(:verbose => true).verbose?.should be_true
      end
    end

    describe ":quiet" do
      it "defaults to false" do
        Ladle::Server.new.quiet?.should be_false
      end

      it "can be overridden" do
        Ladle::Server.new(:quiet => true).quiet?.should be_true
      end
    end

    describe ":timeout" do
      it "defaults to 15 seconds" do
        Ladle::Server.new.timeout.should == 15
      end

      it "can be overridden" do
        Ladle::Server.new(:timeout => 27).timeout.should == 27
      end
    end
  end

  describe "running" do
    def should_be_running
      lambda { TCPSocket.new('localhost', @server.port) }.
        should_not raise_error
    end

    it "blocks until the server is up" do
      @server.start
      should_be_running
    end

    it "returns the server object" do
      @server.start.should be(@server)
    end

    it "is safe to invoke twice (in the same thread)" do
      @server.start
      lambda { @server.start }.should_not raise_error
    end

    it "can be stopped then started again" do
      @server.start
      @server.stop
      @server.start
      lambda { TCPSocket.new('localhost', @server.port) }.
        should_not raise_error
    end

    it "throws an exception when the server doesn't start up" do
      old_stderr, $stderr = $stderr, StringIO.new

      @server = create_server(:more_args => ["--fail", "before_start"])
      lambda { @server.start }.should raise_error(/LDAP server failed to start/)
      $stderr.string.should == "ApacheDS process failed: FATAL: Expected failure for testing\n"

      $stderr = old_stderr
    end

    it "times out after the specified interval" do
      @server = create_server(:timeout => 3, :more_args => %w(--fail hang))
      lambda { @server.start }.
        should raise_error(/LDAP server startup did not complete within 3 seconds/)
    end

    it "should use the specified port" do
      @server = create_server(:port => 45678).start
      should_be_running
    end
  end

  describe "data" do
    def with_ldap
      @server.start
      Net::LDAP.open(ldap_parameters) do |ldap|
        return yield ldap
      end
    end

    def ldap_search(filter, base=nil)
      with_ldap { |ldap|
        ldap.search(
          :base => base || 'dc=example,dc=org',
          :filter => filter
        )
      }
    end

    def ldap_parameters
      @ldap_parameters ||= {
        :host => 'localhost', :port => @server.port,
        :auth => { :method => :anonymous }
      }
    end

    describe "the default set" do
      it "has 26 people" do
        ldap_search(Net::LDAP::Filter.pres('uid')).should have(26).people
      end

      it "has 1 group" do
        ldap_search(Net::LDAP::Filter.pres('ou')).should have(1).group
      end

      it "has given names" do
        ldap_search(Net::LDAP::Filter.pres('uid')).
          select { |res| !res[:givenname] || res[:givenname].empty? }.should == []
      end

      it "has e-mail addresses" do
        ldap_search(Net::LDAP::Filter.pres('uid')).
          select { |res| !res[:mail] || res[:mail].empty? }.should == []
      end

      it "can be searched by value" do
        ldap_search(Net::LDAP::Filter.eq(:givenname, 'Josephine')).
          collect { |res| res[:uid].first }.should == %w(jj243)
      end
    end
  end
end
