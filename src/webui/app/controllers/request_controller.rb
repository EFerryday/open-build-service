class RequestController < ApplicationController

  def index
    redirect_to :action => "list_req"
  end

  def list_req
    @user ||= Person.find( :login => session[:login] )

    @iprojects = @user.involved_projects.each.map {|x| x.name}.sort

    unless @iprojects.empty?
      predicate = @iprojects.map {|item| "action/target/@project='#{item}'"}.join(" or ")
      predicate2 = @iprojects.map {|item| "submit/target/@project='#{item}'"}.join(" or ") # old, to be removed later
      predicate = "(#{predicate} or #{predicate2}) and state/@name='new'"
      @requests_for_me = Collection.find :what => :request, :predicate => predicate
      @requests_by_me = Collection.find :what => :request, :predicate => "state/@name='new' and state/@who='#{session[:login]}'"

      # Do we really need this or is just caused by messed up data in DB ?
      @requests_by_me.each do |req|
        if not req.has_element? :state
          @requests_by_me.delete_element req
        end
      end
    end

  end

  def diff
    diff = Diff.find( :id => params[:id])
    @requests = [diff]
    @id = diff.data.attributes["id"]
    @state = diff.state.data.attributes["name"]
    @type = diff.action.data.attributes["type"]
    if @type=="submit"
      @src_project = diff.action.source.project
      @src_pkg = diff.action.source.package
    end
    @target_project = Project.find diff.action.target.project
    @target_pkg = diff.action.target.package
    @is_author = diff.has_element? "//state[@name='new' and @who='#{session[:login]}']"
    @is_maintainer = @target_project.is_maintainer? session[:login]

    if @type == "submit"
      transport ||= ActiveXML::Config::transport_for(:project)
      path = "/source/%s/%s?opackage=%s&oproject=%s&cmd=diff&expand=1" %
               [CGI.escape(@src_project), CGI.escape(@src_pkg), CGI.escape(@target_pkg), CGI.escape(@target_project.name)]
      if diff.action.source.has_element? 'rev'
        path += "&rev=#{diff.action.source.rev}"
      end
      begin
        @diff_text =  transport.direct_http URI("https://#{path}"), :method => "POST", :data => ""
      rescue Object => e
        @diff_error = e.message
      end
    end
    @revoke_own = (["revoke"].include? params[:changestate]) ? true : false
  
  end
 

  def submitreq
    changestate = params['commit']
    case changestate
      when 'Accept'
        changestate = 'accepted'
      when 'Decline'
        changestate = 'declined'
      when 'Revoke'
        changestate = 'revoked'
      else
        changestate = nil
    end

    reason = "unknown changestate #{changestate}"

    if (changestate=="accepted" || changestate=="declined" || changestate=="revoked")
      reason = params[:reason]
      id = params[:id]
      transport ||= ActiveXML::Config::transport_for(:project)
      path = "/request/#{id}?newstate=#{changestate}&cmd=changestate"
      begin
        transport.direct_http URI("https://#{path}"), :method => "POST", :data => reason
        flash[:note] = "Submit request #{changestate}!"
        redirect_to :action => "list_req"
        return
      rescue ActiveXML::Transport::ForbiddenError => e
        reason = e.message
      end
    end

    flash[:error] = reason
    redirect_to :action => "list_req"

  end

end
