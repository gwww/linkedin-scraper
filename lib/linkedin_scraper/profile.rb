# -*- encoding: utf-8 -*-
module Linkedin
  class Profile

    USER_AGENTS = ["Windows IE 6", "Windows IE 7", "Windows Mozilla", "Mac Safari", "Mac Firefox", "Mac Mozilla", "Linux Mozilla", "Linux Firefox", "Linux Konqueror"]
    ATTRIBUTES = %w(
    name
    first_name
    last_name
    title
    location
    number_of_connections
    country
    industry
    summary
    picture
    projects
    linkedin_url
    education
    groups
    websites
    languages
    skills
    certifications
    publications
    courses
    organizations
    past_companies
    current_companies
    recommended_visitors)

    attr_reader :page, :linkedin_url

    def self.get_profile(url, options = {})
      Linkedin::Profile.new(url, options)
    rescue => e
      puts e
    end

    def initialize(url, options = {})
      @linkedin_url = url
      @options = options
      @page = http_client.get(url)
      @page.css('br').each{ |br| br.replace("\n")  }
    end

    def name
      "#{first_name} #{last_name}"
    end

    def first_name
      @first_name ||= get_text(page, '.fn').split(' ',2)[0]
    end

    def last_name
      @last_name ||= get_text(page, '.fn').split(' ',2)[1]
    end

    def title
      @title ||= get_text(page, '.title')
    end

    def location
      @location ||= get_text(page,'.locality').split(',').first
    end

    def country
      @country ||= get_text(page,'.locality').split(',').last.strip
    end

    def number_of_connections
      @connections ||= get_text(page,'.member-connections').match(/\d+\+?/)[0]
    end

    def industry
      @industry ||= (@page.search("#demographics .descriptor")[-1].text.gsub(/\s+/, " ").strip if @page.at("#demographics .descriptor"))
    end

    def summary
      @summary ||= get_text(page,'#summary .description',:nojoin)
    end

    def picture
      @picture ||= (@page.at('.profile-picture img').attributes.values_at('src','data-delayed-url').compact.first.value.strip if @page.at('.profile-picture img'))
    end

    def skills
      @skills ||= @page.search(".pills .skill").map do |skill| 
        skill.text.strip
      end
    end

    def past_companies
      @past_companies ||= get_companies().reject { |c| c[:end_date] == "Present"}
    end

    def current_companies
      @current_companies ||= get_companies().find_all{ |c| c[:end_date] == "Present"}
    end

    def education
      @education ||= @page.search(".schools .school").map do |item|
        edu = {}
        edu[:name] = get_text(item,'.item-title')
        edu[:description] = get_text(item,'.item-subtitle')
        edu[:degree] = get_text(item,'.item-subtitle').split(',')[0].to_s.strip
        edu[:major] = get_text(item,'.item-subtitle').split(',')[1].to_s.strip
        edu[:period] = get_text(item,'.date-range')
        edu[:start_date], edu[:end_date], d = parse_date3(edu[:period])
        edu
      end
    end

    def websites
      @websites ||= @page.search(".websites li").flat_map do |site|
        url = site.at("a")["href"]
        CGI.parse(URI.parse(url).query)["url"]
      end
    end

    def groups
      @groups ||= @page.search("#groups .group .item-title").map do |item|
        name = item.text.gsub(/\s+|\n/, " ").strip
        link = item.at("a")['href']
        { :name => name, :link => link }
      end
    end

    def organizations
      @organizations ||= @page.search("#organizations ul li").map do |item|
        org = {}
        org[:name] = get_text(item,'.item-title')
        org[:position] = get_text(item,'.item-subtitle')
        org[:start_date], org[:end_date], duration = parse_date3(
          get_text(item, '.date-range').gsub(/Starting/i, ''))
        org
      end
    end

    def languages
      @languages ||= @page.search("#languages ul li").map do |item|
        lang = {}
        lang[:language] = get_text(item,'.name')
        lang[:proficiency] = get_text(item,'.proficiency')
        lang
      end
    end

    def certifications
      @certifications ||= @page.search(".certifications .certification").map do |item|
        cert = {}
        cert[:name] = get_text(item,'.item-title')
        cert[:authority] = get_text(item,'.item-subtitle')
        cert[:license] = get_text(item, '.specifics/.licence-number')
        cert[:start_date] = parse_date3(get_text(item,'.date-range'))[0]
        cert
      end
    end

    def publications
      @publications ||= @page.search("#publications .publication").map do |item|
        pub = {}
        pub[:name] = get_text(item,'.item-title')
        pub[:publication] = get_text(item,'.item-subtitle')
        pub[:description] = get_text(item,'.description',:nojoin)
        pub[:start_date] = parse_date3(get_text(item,'.date-range'))[0]
        pub
      end
    end

    def courses
      @courses ||= @page.search('#courses .course').map do |course|
        { name: get_text(course,'') }
      end
    end

    def recommended_visitors
      @recommended_visitors ||= @page.search(".insights .browse-map/ul/li.profile-card").map do |visitor|
        v = {}
        v[:link] = visitor.at("a")["href"]
        v[:name] = visitor.at("h4/a").text
        if visitor.at(".headline")
          v[:title] = visitor.at(".headline").text.gsub("...", " ").split(" at ").first
          v[:company] = visitor.at(".headline").text.gsub("...", " ").split(" at ")[1]
        end
        v
      end
    end

    def projects
      @projects ||= @page.search("#projects .project").map do |project|
        p = {}
        p[:start_date], p[:end_date], duration = 
          parse_date3(get_text(project,'.meta'))
        p[:title] = get_text(project,'.item-title')
        p[:link] =  CGI.parse(URI.parse(project.at(".item-title a")['href']).query)["url"][0] rescue nil
        p[:description] = get_text(project,'.description',:nojoin)
        p[:associates] = project.search(".contributors .contributor").map{ |c|
          c.at("a").text 
        } rescue nil
        p
      end
    end

    def to_json
      require "json"
      ATTRIBUTES.reduce({}){ |hash,attr| hash[attr.to_sym] = self.send(attr.to_sym);hash }.to_json
    end

    private

    def get_companies()
      return @companies if @companies

      @companies = []
      @page.search(".positions .position").each do |node|
        company = {}
        company[:title] = get_text(node,'.item-title')
        company[:company] = get_text(node,'.item-subtitle')
        company[:description] = get_text(node,'.description',:nojoin)
        company[:start_date], company[:end_date], company[:duration] = 
            parse_date3(node.at(".meta").text)

        eompany_link = node.at(".item-subtitle").at("a")["href"] rescue nil
        if company_link
          result = get_company_details(company_link)
          @companies << company.merge!(result)
        else
          @companies << company
        end
      end
      @companies
    end

    def get_company_details(_link)
      link = _link.match(/^https?:\/\//) ? _link : "https://www.linkedin.com/#{_link}"
      result = {linkedin_company_url: link}
      page = http_client.get(link)
      result[:url] = get_text(page,'.basic-info-about/ul/li/p/a')

      node_2 = page.at(".basic-info-about/ul")
      if node_2
        node_2.search("p").zip(node_2.search("h4")).each do |value, title|
          result[title.text.gsub(" ", "_").downcase.to_sym] = value.text.strip
        end
      end
      result[:address] = page.at(".vcard.hq").at(".adr").text.gsub("\n", " ").strip if page.at(".vcard.hq")
      result
    end

    def get_text( container, selector, join_lines=:join )
      regex = (join_lines == :join) ? %r{\s+} : %r{ +}
      element = selector.to_s.length > 0 ? container.at(selector) : container
      element ? element.text.gsub(regex, ' ').strip : ''
    end

    def parse_date(date)
      date = "#{date}-01-01" if date =~ /^(19|20)\d{2}$/
      Date.parse(date)
    end

    def parse_date3(date)
      date[/(^Starting )*/] = ''
      if date.match /(.*) \((.*)\)/
          date = $1
          duration = $2
      end
      start_date, end_date = date.split(" – ")
      end_date = (end_date =~ /^present/i) ? 'Present' : parse_date(end_date) if !end_date.nil?
      [parse_date(start_date), end_date, duration]
    end

    def http_client
      Mechanize.new do |agent|
        agent.user_agent_alias = USER_AGENTS.sample
        unless @options.empty?
          agent.set_proxy(@options[:proxy_ip], @options[:proxy_port], 
                          @options[:username], @options[:password])
        end
        agent.max_history = 0
      end
    end
  end
end
