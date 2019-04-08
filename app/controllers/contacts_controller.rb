# This file is a part of Redmine CRM (redmine_contacts) plugin,
# customer relationship management plugin for Redmine
#
# Copyright (C) 2010-2018 RedmineUP
# http://www.redmineup.com/
#
# redmine_contacts is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# redmine_contacts is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with redmine_contacts.  If not, see <http://www.gnu.org/licenses/>.

class ContactsController < ApplicationController
  unloadable

  Mime::Type.register 'text/x-vcard', :vcf
  Mime::Type.register 'application/vnd.ms-excel', :xls

  default_search_scope :contacts

  before_action :find_contact, :only => [:show, :edit, :update, :destroy, :load_tab]
  before_action :find_project, :only => [:new, :create]
  before_action :authorize, :only => [:create, :new]
  before_action :authorize_contacts, :only => [:edit, :update, :destroy]
  before_action :find_optional_project, :only => [:index, :contacts_notes, :edit_mails, :send_mails, :bulk_update]

  accept_rss_auth :index, :show
  accept_api_auth :index, :show, :create, :update, :destroy

  helper :attachments
  helper :contacts
  include ContactsHelper
  helper :watchers
  helper :deals
  helper :notes
  helper :custom_fields
  include CustomFieldsHelper
  helper :context_menus
  include WatchersHelper
  helper :sort
  include SortHelper
  helper :queries
  include QueriesHelper
  helper :crm_queries
  include CrmQueriesHelper
  include ApplicationHelper
  include NotesHelper

  def index
    retrieve_crm_query('contact')
    sort_init(@query.sort_criteria.empty? ? [['last_name', 'asc'], ['first_name', 'asc']] : @query.sort_criteria)
    sort_update(@query.sortable_columns)
    @query.sort_criteria = sort_criteria.to_a
    if @query.valid?
      case params[:format]
      when 'csv', 'xls', 'vcf'
        @limit = Setting.issues_export_limit.to_i
        if Redmine::VERSION::STRING < '3.2' && params[:columns] == 'all'
          @query.column_names = @query.available_columns.map(&:name)
        end
      when 'atom'
        @limit = Setting.feeds_limit.to_i
      when 'xml', 'json'
        @offset, @limit = api_offset_and_limit
      else
        @limit = per_page_option
      end
      @contacts_count = @query.object_count
      @contacts_pages = Paginator.new(@contacts_count, @limit, params['page'])
      @offset ||= @contacts_pages.offset
      @contact_count_by_group = @query.object_count_by_group
      @contacts = @query.results_scope(
        :include => [:avatar],
        :search => params[:search],
        :order => sort_clause,
        :limit  =>  @limit,
        :offset =>  @offset
      )
      @filter_tags = @query.filters['tags'] && @query.filters['tags'][:values]
      respond_to do |format|
        format.html {
          unless request.xhr?
            last_notes
            @tags = Contact.available_tags(:project => @project)
          else
            render :partial => contacts_list_style, :layout => false
          end
        }
        format.api
        format.atom { render_feed(@contacts, :title => "#{@project || Setting.app_title}: #{l(:label_contact_plural)}") }
      end
    else
      respond_to do |format|
        format.html {
          last_notes
          @tags = Contact.available_tags(:project => @project)
          render(:template => 'contacts/index', :layout => !request.xhr?)
        }
        format.any(:atom, :csv, :pdf) { render(:nothing => true) }
        format.api { render_validation_errors(@query) }
      end
    end
  end

  def show
    find_contact_issues
    respond_to do |format|
      format.js if request.xhr?
      format.html { @contact.viewed }
      format.api
      format.atom { render_feed(@notes, :title => "#{@contact.name || Setting.app_title}: #{l(:label_crm_note_plural)}") }
      format.vcf { send_data(contact_to_vcard(@contact), :filename => "#{@contact.name}.vcf", :type => 'text/x-vcard;', :disposition => 'attachment') }
    end
  end

  def edit
  end

  def update
    @contact.safe_attributes = params[:contact]
    @contact.save_attachments(params[:attachments] || (params[:contact] && params[:contact][:uploads]))
    if @contact.save
      flash[:notice] = l(:notice_successful_update)
      remove_old_avatars
      respond_to do |format|
        format.html { redirect_to :action => 'show', :project_id => params[:project_id], :id => @contact }
        format.api  { render_api_ok }
      end
    else
      respond_to do |format|
        format.html { render 'edit', :project_id => params[:project_id], :id => @contact }
        format.api  { render_validation_errors(@contact) }
      end
    end
  end

  def destroy
    if @contact.destroy
      flash[:notice] = l(:notice_successful_delete)
    else
      flash[:error] = l(:notice_unsuccessful_save)
    end
    respond_to do |format|
      format.html { redirect_back_or_default :action => 'index', :project_id => params[:project_id] }
      format.api  { render_api_ok }
    end
  end

  def new
    @duplicates = []
    @contact = Contact.new
    @contact.safe_attributes = params[:contact] if params[:contact] && params[:contact].is_a?(Hash)
  end

  def create
    @contact = Contact.new(:project => @project, :author => User.current)
    @contact.safe_attributes = params[:contact]
    @contact.save_attachments(params[:attachments] || (params[:contact] && params[:contact][:uploads]))
    if @contact.save
      flash[:notice] = l(:notice_successful_create)
      remove_old_avatars
      respond_to do |format|
        format.html { redirect_to (params[:continue] ? { :action => 'new', :project_id => @project } : { :action => 'show', :project_id => @project, :id => @contact }) }
        format.js
        format.api { redirect_on_create(params) }
      end
    else
      respond_to do |format|
        format.api  { render_validation_errors(@contact) }
        format.js { render :action => 'new' }
        format.html { render :action => 'new' }
      end
    end
  end

  def contacts_notes
    unless request.xhr?
      @tags = Contact.available_tags(:project => @project)
    end

    contacts = find_contacts(false)

    joins = " "
    joins << " LEFT OUTER JOIN #{Contact.table_name} ON #{Note.table_name}.source_id = #{Contact.table_name}.id AND #{Note.table_name}.source_type = 'Contact' "
    cond = "(1 = 1) "
    cond << "and (#{Contact.table_name}.id in (#{contacts.any? ? contacts.map(&:id).join(', ') : 'NULL'})"
    cond << " )"
    cond << " and (LOWER(#{Note.table_name}.content) LIKE '%#{params[:search_note].downcase}%')" if params[:search_note] and request.xhr?
    cond << " and (#{Note.table_name}.author_id = #{params[:note_author_id]})" if !params[:note_author_id].blank?
    cond << " and (#{Note.table_name}.type_id = #{params[:type_id]})" if !params[:type_id].blank?

    scope = Note.joins(joins).where(cond).order("#{Note.table_name}.created_on DESC")
    @notes_pages = Paginator.new(scope.count, 20, params['page'])
    @notes = scope.limit(20).offset(@notes_pages.offset)

    respond_to do |format|
      format.html { render :partial => "notes/notes_list", :layout => false, :locals => { :notes => @notes, :notes_pages => @notes_pages } if request.xhr? }
      format.xml { render :xml => @notes }
      format.csv { send_data(notes_to_csv(@notes), :type => 'text/csv; header=present', :filename => 'notes.csv') }
      format.atom { render_feed(@notes, :title => "#{l(:label_crm_note_plural)}") }
    end
  end

  def context_menu
    @project = Project.find(params[:project_id]) unless params[:project_id].blank?
    @contacts = Contact.visible.where(:id => params[:selected_contacts])
    @contact = @contacts.first if (@contacts.size == 1)
    @can = { :edit => (@contact && @contact.editable?) || (@contacts && @contacts.collect { |c| c.editable? }.inject { |memo, d| memo && d }),
             :create => (@project && User.current.allowed_to?(:add_contacts, @project)),
             :delete => @contacts.collect { |c| c.deletable? }.inject { |memo, d| memo && d },
             :send_mails => @contacts.collect { |c| c.send_mail_allowed? && !c.primary_email.blank? }.inject { |memo, d| memo && d }
          }

    render :layout => false
  end

  def bulk_destroy
    @contacts = Contact.deletable.where(:id => params[:ids])
    raise ActiveRecord::RecordNotFound if @contacts.empty?
    @contacts.each(&:destroy)
    redirect_back_or_default({ :action => 'index', :project_id => params[:project_id] })
  end

  def load_tab
  end

  private

  def find_contact_issues
    scope = @contact.issues
    scope = scope.open unless RedmineContacts.settings[:show_closed_issues]
    @contact_issues_count = scope.visible.count
    @contact_issues = scope.visible.order("#{Issue.table_name}.status_id, #{Issue.table_name}.updated_on DESC").limit(10)
  end

  def remove_old_avatars
    params_hash = params.respond_to?(:to_unsafe_hash) ? params.to_unsafe_hash : params
    avatar_params = params_hash[:attachments].find { |_k, v| v['description'] == 'avatar' }.try(:last) if params_hash[:attachments].present?
    return unless avatar_params
    avatar_id = avatar_params['token'].split('.').first.to_i
    @contact.attachments.where(:description => 'avatar').where('id != ?', avatar_id).destroy_all if @contact.avatar
  end

  def last_notes(count = 5)
    scope = ContactNote.where({})
    scope = scope.where("#{Project.table_name}.id = ?", @project.id) if @project
    scope = scope.includes(:attachments)

    @last_notes = scope.visible.
                        limit(count).
                        order("#{ContactNote.table_name}.created_on DESC").uniq
  end

  def find_contact
    @contact = Contact.find(params[:id])
    unless @contact.visible?
      deny_access
      return
    end
    project_id = (params[:contact] && params[:contact][:project_id]) || params[:project_id]
    @project = Project.find_by_identifier(project_id)
    @project ||= @contact.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_contacts(pages = true)
    @tag = RedmineCrm::TagList.from(params[:tag]) unless params[:tag].blank?

    scope = Contact.where({})
    scope = scope.where("#{Contact.table_name}.job_title = ?", params[:job_title]) unless params[:job_title].blank?
    scope = scope.where("#{Contact.table_name}.assigned_to_id = ?", params[:assigned_to_id]) unless params[:assigned_to_id].blank?
    scope = scope.where("#{Contact.table_name}.is_company = ?", params[:query]) unless (params[:query].blank? || params[:query] == '2' || params[:query] == '3')
    scope = scope.where("#{Contact.table_name}.author_id = ?", User.current) if params[:query] == '3'

    case params[:query]
    when '2' then scope = scope.order_by_creation
    when '3' then scope = scope.order_by_creation
    else scope = scope.order_by_name
    end

    scope = scope.by_project(@project)

    params[:search].split(' ').collect{ |search_string| scope = scope.live_search(search_string) } if !params[:search].blank?
    scope = scope.visible

    scope = scope.tagged_with(params[:tag]) if !params[:tag].blank?
    scope = scope.tagged_with(params[:notag], :exclude => true) if !params[:notag].blank?

    @contacts_count = scope.count
    @contacts = scope

    if pages
      page_size = params[:page_size].blank? ? 20 : params[:page_size].to_i
      @contacts_pages = Paginator.new(self, @contacts_count, page_size, params[:page])
      @offset = @contacts_pages.offset
      @limit =  @contacts_pages.items_per_page

      @contacts = @contacts.eager_load([:tags, :avatar]).limit(@limit).offset(@offset)

      fake_name = @contacts.first.name if @contacts.length > 0
    end
    @contacts
  end

  # Filter for bulk issue operations
  def bulk_find_contacts
    @contacts = Deal.find_all_by_id(params[:id] || params[:ids], :include => :project)
    raise ActiveRecord::RecordNotFound if @contact.empty?
    if @contacts.detect { |contact| !contact.visible? }
      deny_access
      return
    end
    @projects = @contacts.collect(&:projects).compact.uniq
    @project = @projects.first if @projects.size == 1
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_project(project_id = nil)
    project_id ||= (params[:contact] && params[:contact][:project_id]) || params[:project_id]
    @project = Project.find(project_id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def authorize_contacts(action = params[:action], _global = false)
    case action.to_s
    when 'edit', 'update'
      @contact.editable? ? true : deny_access
    when 'destroy'
      @contact.deletable? ? true : deny_access
    else
      deny_access
    end
  end

  def redirect_on_create(options)
    if options[:redirect_on_success].to_s.match('^(http|https):\/\/')
      redirect_to options[:redirect_on_success].to_s
    else
      render :action => 'show', :status => :created, :location => contact_url(@contact)
    end
  end
end
