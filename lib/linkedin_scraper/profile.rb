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
      @first_name ||= (@page.at(".fn").text.split(" ", 2)[0].strip if @page.at(".fn"))
    end

    def last_name
      @last_name ||= (@page.at(".fn").text.split(" ", 2)[1].strip if @page.at(".fn"))
    end

    def title
      @title ||= (@page.at(".title").text.gsub(/\s+/, " ").strip if @page.at(".title"))
    end

    def location
      @location ||= (@page.at(".locality").text.split(",").first.strip if @page.at(".locality"))
    end

    def number_of_connections
      @connections ||= (@page.at(".member-connections").text.match(/[0-9]+[\+]{0,1}/)[0]) if @page.at(".member-connections")
    end

    def country
      @country ||= (@page.at(".locality").text.split(",").last.strip if @page.at(".locality"))
    end

    def industry
      @industry ||= (@page.search("#demographics .descriptor")[-1].text.gsub(/\s+/, " ").strip if @page.at("#demographics .descriptor"))
    end

    def summary
      @summary ||= (@page.at("#summary .description").text.gsub(/ +/, " ").strip if @page.at("#summary .description"))
    end

    def picture
      @picture ||= (@page.at('.profile-picture img').attributes.values_at('src','data-delayed-url').compact.first.value.strip if @page.at('.profile-picture img'))
    end

    def skills
      @skills ||= (@page.search(".pills .skill").map { |skill| skill.text.strip if skill.text } rescue nil)
    end

    def past_companies
      @past_companies ||= get_companies().reject { |c| c[:end_date] == "Present"}
    end

    def current_companies
      @current_companies ||= get_companies().find_all{ |c| c[:end_date] == "Present"}
    end

    def education
      @education ||= @page.search(".schools .school").map do |item|
        name = item.at("h4").text.gsub(/\s+|\n/, " ").strip if item.at("h4")
        desc = item.search("h5").last.text.gsub(/\s+|\n/, " ").strip if item.search("h5").last
        degree = item.search("h5").last.at(".degree").text.gsub(/\s+|\n/, " ").strip.gsub(/,$/, "") if item.search("h5").last.at(".degree")
        major = item.search("h5").last.at(".major").text.gsub(/\s+|\n/, " ").strip      if item.search("h5").last.at(".major")
        period = item.at(".date-range").text.gsub(/\s+|\n/, " ").strip if item.at(".date-range")
        start_date, end_date = item.at(".date-range").text.gsub(/\s+|\n/, " ").strip.split(" – ") rescue nil
        {:name => name, :description => desc, :degree => degree, :major => major, :period => period, :start_date => start_date, :end_date => end_date }
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
      @organizations ||= @page.search("#background-organizations .section-item").map do |item|
        name = item.at(".summary").text.gsub(/\s+|\n/, " ").strip rescue nil
        start_date, end_date = item.at(".organizations-date").text.gsub(/\s+|\n/, " ").strip.split(" – ") rescue nil
        start_date = Date.parse(start_date) rescue nil
        end_date = Date.parse(end_date)   rescue nil
        { :name => name, :start_date => start_date, :end_date => end_date }
      end
    end

    def languages
      @languages ||= @page.search(".background-languages #languages ol li").map do |item|
        language = item.at("h4").text rescue nil
        proficiency = item.at("div.languages-proficiency").text.gsub(/\s+|\n/, " ").strip rescue nil
        { :language => language, :proficiency => proficiency }
      end
    end

    def certifications
      @certifications ||= @page.search(".certifications .certification").map do |item|
        name       = item.at(".item-title").text.gsub(/\s+|\n/, " ").strip rescue nil
        authority  = item.at(".item-subtitle").text.gsub(/\s+|\n/, " ").strip rescue nil
        license    = item.at(".specifics/.licence-number").text.gsub(/\s+|\n/, " ").strip rescue nil
        start_date, end_date, duration = parse_date2(item.at(".date-range").text)
        { :name => name, :authority => authority, :license => license, :start_date => start_date }
      end
    end

    def publications
      @publications ||= @page.search("#publications .publication").map do |item|
        name = item.at(".item-title").text.gsub(/\s+|\n/, " ").strip rescue nil
        publication = item.at(".item-subtitle").text.gsub(/\s+|\n/, " ").strip rescue nil
        description = item.at(".description").text.gsub(/\s+|\n/, " ").strip rescue nil
        start_date, end_date, duration = parse_date2(item.at(".date-range").text)
        { :name => name, :publication => publication, :description => description, :start_date => start_date }
      end
    end

    def courses
      @courses ||= @page.search(".courses-list .course").map do |course|
        name = course.text.gsub(/\s+|\n/, " ").strip rescue nil
        { :name => name }
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

        p[:start_date], p[:end_date], duration = parse_date2(project.at(".meta").text)

        p[:title] = project.at(".item-title").text
        p[:link] =  CGI.parse(URI.parse(project.at(".item-title a")['href']).query)["url"][0] rescue nil
        p[:description] = project.at(".description").text rescue nil
        p[:associates] = project.search(".contributors .contributor").map{ |c| c.at("a").text } rescue nil
        p
      end
    end

    def to_json
      require "json"
      ATTRIBUTES.reduce({}){ |hash,attr| hash[attr.to_sym] = self.send(attr.to_sym);hash }.to_json
    end

    private
    #TODO Bad code Hot fix
    def get_companies()
      if @companies
        return @companies
      else
        @companies = []
      end

      @page.search(".positions .position").each do |node|
        company = {}
        company[:title] = node.at(".item-title").text.gsub(/\s+|\n/, " ").strip if node.at(".item-title")
        company[:company] = node.at(".item-subtitle").text.gsub(/\s+|\n/, " ").strip if node.at(".item-subtitle")
        company[:description] = node.at(".description").text.gsub(/ +/, " ").strip if node.at(".description")

        company[:start_date], company[:end_date], company[:duration] = 
            parse_date2(node.at(".meta").text)
        # start_date, end_date = node.at(".meta").text.strip.split(" – ") rescue nil
        # company[:duration] = node.at(".meta").text[/.*\((.*)\)/, 1]
        # company[:start_date] = parse_date(start_date) rescue nil
        # if end_date && end_date.match(/Present/)
        #   company[:end_date] = "Present"
        # else
        #   company[:start_date] = parse_date(end_date) rescue nil
        # end

        company_link = node.at(".item-subtitle").at("a")["href"] rescue nil
        if company_link
          result = get_company_details(company_link)
          @companies << company.merge!(result)
        else
          @companies << company
        end
      end

      @companies
    end

    def parse_date(date)
      date = "#{date}-01-01" if date =~ /^(19|20)\d{2}$/
      Date.parse(date)
    end

    def parse_date2(date)
      date[/(^Starting )*/] = ''
      if date.match /(.*) \((.*)\)/
          date = $1
          duration = $2
      end
      start_date, end_date = date.split(" – ")
      end_date = (end_date =~ /^present/i) ? 'Present' : parse_date(end_date) if !end_date.nil?
      [parse_date(start_date), end_date, duration]
    end

    def get_company_details(link)
      result = { :linkedin_company_url => get_linkedin_company_url(link) }
      page = http_client.get(result[:linkedin_company_url])

      result[:url] = page.at(".basic-info-about/ul/li/p/a").text if page.at(".basic-info-about/ul/li/p/a")
      node_2 = page.at(".basic-info-about/ul")
      if node_2
        node_2.search("p").zip(node_2.search("h4")).each do |value, title|
          result[title.text.gsub(" ", "_").downcase.to_sym] = value.text.strip
        end
      end
      result[:address] = page.at(".vcard.hq").at(".adr").text.gsub("\n", " ").strip if page.at(".vcard.hq")
      result
    end

    def http_client
      Mechanize.new do |agent|
        agent.user_agent_alias = USER_AGENTS.sample
        unless @options.empty?
          agent.set_proxy(@options[:proxy_ip], @options[:proxy_port], @options[:username], @options[:password])
        end
        agent.max_history = 0
      end
    end

    def get_linkedin_company_url(link)
      http = %r{http://www.linkedin.com/}
      https = %r{https://www.linkedin.com/}
      if http.match(link) || https.match(link)
        link
      else
        "http://www.linkedin.com/#{link}"
      end
    end
  end
end
