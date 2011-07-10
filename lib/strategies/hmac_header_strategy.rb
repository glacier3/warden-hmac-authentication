require 'hmac'
require 'warden'

class Warden::Strategies::HMACHeader < Warden::Strategies::Base
  
  def valid?
    valid = required_headers.all? { |h| headers.include?(h) } && headers.include?("Authorization") && has_timestamp?
    valid = valid && scheme_valid?
    valid
  end

  def authenticate!
    if "" == secret.to_s
      return fail!("Cannot authenticate with an empty secret")
    end
    
    if check_ttl? && !timestamp_valid?
      return fail!("Invalid timestamp")  
    end
    
    #:method => "GET",
    #:date => "Mon, 20 Jun 2011 12:06:11 GMT",
    #:nonce => "TESTNONCE",
    #:path => "/example",
    #:query => {
    #  "foo" => "bar",
    #  "baz" => "foobared"
    #},
    #:headers => {
    #  "Content-Type" => "application/json;charset=utf8",
    #  "Content-MD5" => "d41d8cd98f00b204e9800998ecf8427e"
    #}
    
    if hmac.check_signature(signature, {
        :secret => secret,
        :method => request_method,
        :date => request_timestamp,
        :nonce => nonce,
        :path => request.path,
        :query => params,
        :headers => headers.select {|name, value| optional_headers.include? name}
      })
      success!(retrieve_user)
    else
      fail!("Invalid token passed")
    end
  end
  
  def signature
    headers[auth_header].split(" ")[1]
  end
  
  def params
    request.GET
  end
  
  def headers
    pairs = env.select {|k,v| k.start_with? 'HTTP_'}
        .collect {|pair| [pair[0].sub(/^HTTP_/, '').gsub(/_/, '-'), pair[1]]}
        .sort
     headers = Hash[*pairs.flatten]
     headers   
  end
  
  def request_method
    env['REQUEST_METHOD'].upcase
  end
  
  def retrieve_user
    true
  end
  
  private
    
    
    def config
      env["warden"].config[:scope_defaults][scope][:hmac]
    end
    
    def lowercase_headers

      if @lowercase_headers.nil?
        tmp = headers.map do |name,value|
          [name.downcase, value]
        end
        @lowercase_headers = Hash[*tmp.flatten]
      end

      @lowercase_headers
    end
    
    def required_headers
      headers = [auth_header]
      headers += [nonce_header_name] if nonce_required? 
      headers
    end

    def optional_headers
      (config[:optional_headers] || []) + ["Content-MD5", "Content-Type"]
    end

    def auth_scheme_name
      config[:auth_scheme] || "HMAC"
    end
    
    def scheme_valid?
      headers[auth_header].to_s.split(" ").first == auth_scheme_name
    end
    
    def nonce_header_name
      config[:nonce_header] || "X-#{auth_scheme_name}-Nonce"
    end
    
    def alternate_date_header_name
      config[:alternate_date_header] || "X-#{auth_scheme_name}-Date"
    end

    def date_header
      if headers.include? alternate_date_header_name
        alternate_date_header_name
      else
        "Date"
      end
    end
    
    def auth_header
      config[:auth_header] || "Authorization"
    end

    def auth_param
      config[:auth_param] || "auth"
    end

    def has_timestamp?
      headers.include? date_header
    end
    
    def ttl
      if config.include? :ttl
        config[:ttl].to_i unless config[:ttl].nil?
      else
        900
      end
    end
    
    def check_ttl?
      !ttl.nil?
    end

    def request_timestamp
      headers[date_header]
    end

    def timestamp
      Time.strptime(headers[date_header], '%a, %e %b %Y %T %z') if headers.include? date_header
    end
    
    def timestamp_valid?
      now = Time.now.gmtime.to_i
      timestamp.to_i < (now + clockskew) && timestamp.to_i > (now - ttl)
    end
    
    def nonce
      headers[nonce_header_name]
    end

    def nonce_required?
      !!config[:require_nonce]
    end

    def secret
      @secret ||= config[:secret].respond_to?(:call) ? config[:secret].call(self) : config[:secret]
    end
    
    def clockskew
      config[:clockskew] || 5
    end
    
    def hmac
      HMAC.new(algorithm)
    end

    def algorithm
      config[:algorithm] || "sha1"
    end
    
end

Warden::Strategies.add(:hmac_header, Warden::Strategies::HMACHeader)
