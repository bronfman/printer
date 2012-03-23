require "rubygems"
require "bundler/setup"
require "sinatra"
require 'sinatra/base'
require "resque"

require "jobs"
require "printer"
require "preview"
require "id_generator"
require "content_store"

class WeePrinterBackendServer < Sinatra::Base
  set :views, settings.root + '/../views'
  set :public_folder, settings.root + '/../public'

  get("/")                      { erb :index }
  get("/getting-a-wee-printer") { erb :getting_a_wee_printer }
  get("/api")                   { erb :api }
  get("/publishing")            { erb :publishing }

  get "/preview/show/:preview_id" do
    @preview = Preview.find(params['preview_id'])
    erb :preview
  end

  get "/preview/pending/:preview_id" do
    preview = Preview.find(params['preview_id'])
    if preview
      redirect "/preview/show/#{params['preview_id']}"
    else
      erb :preview_pending
    end
  end

  get "/preview" do
    queue_preview(url_to_process)
  end

  post "/preview" do
    if params['content']
      queue_preview_from_content(params['content'])
    else
      queue_preview(url_to_process)
    end
  end

  get "/print/:printer_id" do
    queue_print(params['printer_id'], url_to_process)
  end

  post "/print/:printer_id" do
    if params['content']
      queue_print_from_content(params['printer_id'], params['content'])
    else
      queue_print(params['printer_id'], url_to_process)
    end
  end

  get "/printer/:printer_id" do
    Printer.new(params['printer_id']).archive_and_return_print_data
  end

  private

  def url_to_process
    params['url'] || env['HTTP_REFERER']
  end

  def queue_print(printer_id, url)
    Resque.enqueue(Jobs::PreparePage, printer_id, url)
    erb :queued
  end

  def queue_preview(url)
    preview_id = IdGenerator.random_id
    Resque.enqueue(Jobs::Preview, preview_id, url)
    redirect "/preview/pending/#{preview_id}"
  end

  def queue_print_from_content(printer_id, content)
    path = ContentStore.write_html_content(content)
    Resque.enqueue(Jobs::PreparePage, printer_id, absolute_url_for_path(path))
    if request.accept?('application/json')
      respond_with_json(response: "ok")
    else
      erb :queued
    end
  end

  def queue_preview_from_content(content)
    preview_id = IdGenerator.random_id
    path = ContentStore.write_html_content(content, preview_id)
    Resque.enqueue(Jobs::Preview, preview_id, absolute_url_for_path(path))
    preview_pending_path = absolute_url_for_path("/preview/pending/#{preview_id}")
    if request.accept?('application/json')
      respond_with_json(location: preview_pending_path)
    else
     redirect preview_pending_path
    end
  end

  def absolute_url_for_path(path)
    request.scheme + "://" + request.host_with_port + path
  end

  def respond_with_json(data)
    headers "Access-Control-Allow-Origin" => "*"
    content_type :json
    MultiJson.encode(data)
  end
end