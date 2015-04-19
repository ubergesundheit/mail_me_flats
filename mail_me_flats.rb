#!/usr/bin/env ruby

require "nokogiri"
require "open-uri"
require "mandrill"
require "json"

@ebay_base_url = "http://kleinanzeigen.ebay.de"
@immoscout_base_url = "http://www.immobilienscout24.de"
@immoscout_json_controller_url = "/Suche/controller/asyncResults.go?searchUrl="

immoscout_search_urls = ENV["IMMOSCOUT_URL"].split(';')
ebay_search_urls = ENV["KLEINANZEIGEN_URL"].split(';')

mandrill = Mandrill::API.new ENV["MANDRILL_APIKEY"]
file = File.open(File.join(File.dirname(File.expand_path(__FILE__)), "seen"), "a+")
@seen = file.readlines

def ebay(search_url)
  doc = Nokogiri::HTML(open("#{@ebay_base_url}#{search_url}"))

  doc.css("#srchrslt-adtable > li").map do |item|
    time_str = item.css(".ad-listitem-addon").text.strip
    time = Time.parse(time_str)
    if time_str.include? "Gestern"
      time = time - 86400
    end
    details = item.css(".ad-listitem-details").text.gsub(/\n\s*/," ").strip
    main = item.css(".ad-listitem-main").text.gsub(/\n\s*/," ").gsub("\r","").strip
    url = "#{@ebay_base_url}#{item.css(".ad-listitem-main > h2 > a").first["href"]}"
    {
      time: time,
      details: details,
      main: main,
      url: url
    } unless @seen.include? "#{url}\n"
  end
end

def immoscout_json(search_url)
  json = JSON.parse(open("#{@immoscout_base_url}#{@immoscout_json_controller_url}#{search_url}").read)

  results = json["searchResult"]["results"]

  results.map do |res|

    expose_link = "#{@immoscout_base_url}/expose/#{res["id"]}"

    expose_title = res["title"]

    expose_details = ""

    begin
      expose_details += "#{res["address"]}"
    rescue
    end

    begin
      expose_details += " #{res["district"]}"
    rescue
    end

    begin
      expose_details += " #{res["attributes"].map(&:values).map { |a| a.reverse.join (" ") }.join(", ")}"
    rescue
    end

    begin
      expose_details += " #{res["checkedAttributes"].join(", ")}"
    rescue
    end

    {
      details: expose_details,
      title: expose_title,
      url: expose_link
    } unless @seen.include? "#{expose_link}\n"
  end


end

def immoscout(search_url)
  immo_doc = Nokogiri::HTML(open("#{@immoscout_base_url}#{search_url}"))

  immo_doc.css("#resultListItems > li").reject { |li| li.css("a").count == 0 }.map do |li|
    expose_href = li.css(".headline-link").first

    expose_title = expose_href.text
    expose_link = "#{@immoscout_base_url}#{expose_href["href"]}"

    expose_details = [
      li.css(".street").text.split(" | ").last,
      li.css(".resultlist_criteria > dl").map { |dl| "#{dl.css("dd").text.strip} #{dl.css("dt").text.strip}" }.join(", "),
      li.css(".criteria_secondary_box > ul > li").map { |li| li.text.strip }.join(", ")
    ].join(", ")

    {
      details: expose_details,
      title: expose_title,
      url: expose_link
    } unless @seen.include? "#{expose_link}\n"
  end
end

begin
  whngs = []
  whngs += ebay_search_urls.map do |url|
    ebay(url)
  end
  whngs += immoscout_search_urls.map do |url|
    immoscout_json(url)
  end

  whngs.flatten!.compact!

  unless whngs.length == 0
    whngs.each_slice(2) do |whngs_f|
      message = {
        subject: ENV["EMAIL_SUBJECT"],
        from_name: ENV["EMAIL_FROM_NAME"],
        text: whngs_f.map { |e| e.values.join " " }.join("\n"),
        to: [{
              email: ENV["EMAIL_TO"],
              name: ENV["EMAIL_TO_NAME"]
             }],
        from_email: ENV["EMAIL_FROM"]
        }
      sending = mandrill.messages.send message
      if sending[0]["status"] == "sent"
        file.write(whngs_f.compact.map { |e| e[:url] }.join("\n")+"\n")
      end
    end
  end

rescue Exception => e
  puts "ERROR: #{e}"
end
