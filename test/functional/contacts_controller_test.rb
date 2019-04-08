# encoding: utf-8
#
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

# encoding: utf-8
require File.expand_path('../../test_helper', __FILE__)

class ContactsControllerTest < ActionController::TestCase
  fixtures :projects,
           :users,
           :roles,
           :members,
           :member_roles,
           :issues,
           :issue_statuses,
           :versions,
           :trackers,
           :projects_trackers,
           :issue_categories,
           :enabled_modules,
           :enumerations,
           :attachments,
           :workflows,
           :custom_fields,
           :custom_values,
           :custom_fields_projects,
           :custom_fields_trackers,
           :time_entries,
           :journals,
           :journal_details,
           :queries

  RedmineContacts::TestCase.create_fixtures(Redmine::Plugin.find(:redmine_contacts).directory + '/test/fixtures/', [:contacts,
                                                                                                                    :contacts_projects,
                                                                                                                    :contacts_issues,
                                                                                                                    :deals,
                                                                                                                    :notes,
                                                                                                                    :tags,
                                                                                                                    :taggings,
                                                                                                                    :queries,
                                                                                                                    :addresses])

  def setup
    RedmineContacts::TestCase.prepare
    User.current = nil
  end

  def test_get_index
    @request.session[:user_id] = 1
    assert_not_nil Contact.find(1)
    compatible_request :get, :index
    assert_response :success
    assert_not_nil contacts_in_list
    assert_select 'a', :html => /Domoway/
    assert_select 'a', :html => /Marat/
    assert_select 'h3', :html => /Tags/
    assert_select 'h3', :html => /Recently viewed/
    assert_select 'div#tags span#single_tags span.tag-label-color a', 'test'
    assert_select 'div#tags span#single_tags span.tag-label-color a', 'main'
  end

  test 'should get index in project' do
    @request.session[:user_id] = 1
    Setting.default_language = 'en'

    compatible_request :get, :index, :project_id => 1
    assert_response :success
    assert_not_nil contacts_in_list
    assert_select 'a', :html => /Domoway/
    assert_select 'a', :html => /Marat/
    assert_select 'h3', :html => /Tags/
    assert_select 'h3', :html => /Recently viewed/
  end

  def test_should_not_absolute_links
    @request.session[:user_id] = 1

    compatible_request :get, :index
    assert_response :success
    assert_no_match %r{localhost}, @response.body
  end

  def test_should_get_index_deny_user_in_project
    @request.session[:user_id] = 5

    compatible_request :get, :index, :project_id => 1
    assert_response :redirect
  end

  def test_get_show
    @request.session[:user_id] = 2
    Setting.default_language = 'en'

    compatible_request :get, :show, :id => 3, :project_id => 1
    assert_response :success

    assert_not_nil contacts_in_list
    assert_select 'h1', :html => /Domoway/
    assert_select 'div#tags_data span.tag-label-color a', 'main'
    assert_select 'div#tags_data span.tag-label-color a', 'test'
    assert_select 'div#tab-placeholder-contacts'
    assert_select 'div#comments div#notes table.note_data td.name h4', 4
    assert_select 'h3', 'Recently viewed'
  end

  def test_get_show_with_long_note
    long_note = 'A' * 1500
    Contact.find(3).notes.create(:content => long_note, :author_id => 1)
    @request.session[:user_id] = 2
    Setting.default_language = 'en'

    compatible_request :get, :show, :id => 3, :project_id => 1
    assert_response :success
    assert_select '.note a', '(read more)'
  end

  def test_get_new
    @request.session[:user_id] = 2
    compatible_request :get, :new, :project_id => 1
    assert_response :success
    assert_select 'input#contact_first_name'
  end

  def test_get_new_without_permission
    @request.session[:user_id] = 4
    compatible_request :get, :new, :project_id => 1
    assert_response :forbidden
  end

  def test_post_create
    @request.session[:user_id] = 1
    assert_difference 'Contact.count' do
      compatible_request :post, :create, :project_id => 1, :contact => { :company => 'OOO "GKR"',
                                                                         :is_company => 0,
                                                                         :job_title => 'CFO',
                                                                         :assigned_to_id => 3,
                                                                         :tag_list => 'test,new',
                                                                         :last_name => 'New',
                                                                         :middle_name => 'Ivanovich',
                                                                         :first_name => 'Created' }
    end

    assert_redirected_to :controller => 'contacts', :action => 'show', :id => Contact.last.id, :project_id => Contact.last.project

    contact = Contact.where(:first_name => 'Created', :last_name => 'New', :middle_name => 'Ivanovich').first
    assert_not_nil contact
    assert_equal 'CFO', contact.job_title
    assert_equal ['new', 'test'], contact.tag_list.sort
    assert_equal 3, contact.assigned_to_id
  end

  def test_post_create_without_permission
    @request.session[:user_id] = 4
    compatible_request :post, :create, :project_id => 1, :contact => { :company => 'OOO "GKR"',
                                                                       :is_company => 0,
                                                                       :job_title => 'CFO',
                                                                       :assigned_to_id => 3,
                                                                       :tag_list => 'test,new',
                                                                       :last_name => 'New',
                                                                       :middle_name => 'Ivanovich',
                                                                       :first_name => 'Created' }
    assert_response :forbidden
  end

  def test_get_edit
    @request.session[:user_id] = 1
    compatible_request :get, :edit, :id => 1
    assert_response :success
    assert_select 'h2', /Editing Contact Information/
  end

  def test_get_edit_with_duplicates
    contact = Contact.find(3)
    contact_clone = contact.dup
    contact_clone.project = contact.project
    contact_clone.save!

    @request.session[:user_id] = 2
    Setting.default_language = 'en'

    compatible_request :get, :edit, :id => 3
    assert_response :success
    assert_select 'div#duplicates', 1
    assert_select 'div#duplicates h3', /Possible duplicates/
  ensure
    contact_clone.delete
  end

  def test_put_update
    @request.session[:user_id] = 1

    contact = Contact.find(1)
    new_firstname = 'Fist name modified by ContactsControllerTest#test_put_update'

    compatible_request :put, :update, :id => 1, :project_id => 1, :contact => { :first_name => new_firstname }
    assert_redirected_to :action => 'show', :id => '1', :project_id => 1
    contact.reload
    assert_equal new_firstname, contact.first_name
  end

  def test_post_destroy
    @request.session[:user_id] = 1
    compatible_request :post, :destroy, :id => 1, :project_id => 'ecookbook'
    assert_redirected_to :action => 'index', :project_id => 'ecookbook'
    assert_equal 0, Contact.where(:id => [1]).count
  end

  def test_post_bulk_destroy
    @request.session[:user_id] = 1

    compatible_request :post, :bulk_destroy, :ids => [1, 2, 3]
    assert_redirected_to :controller => 'contacts', :action => 'index'

    assert_equal 0, Contact.where(:id => [1, 2, 3]).count
  end

  def test_post_bulk_destroy_without_permission
    @request.session[:user_id] = 4
    assert_raises ActiveRecord::RecordNotFound do
      compatible_request :post, :bulk_destroy, :ids => [1, 2]
    end
  end

  def test_get_contacts_notes
    @request.session[:user_id] = 2

    compatible_request :get, :contacts_notes
    assert_response :success
    assert_select 'h2', /All notes/
    assert_select 'div#contacts_notes table.note_data div.note.content.preview', /Note 1/
  end

  def test_get_context_menu
    @request.session[:user_id] = 1
    compatible_xhr_request :get, :context_menu, :back_url => '/projects/contacts-plugin/contacts', :project_id => 'ecookbook', :ids => ['1', '2']
    assert_response :success
  end

  def test_post_index_with_search
    @request.session[:user_id] = 1
    compatible_xhr_request :post, :index, :search => 'Domoway'
    assert_response :success
    assert_match 'contacts?search=Domoway', response.body
    assert_select 'a', :html => /Domoway/
  end

  def test_post_index_with_search_in_project
    @request.session[:user_id] = 1
    compatible_xhr_request :post, :index, :search => 'Domoway', :project_id => 'ecookbook'
    assert_response :success
    assert_match 'contacts?search=Domoway', response.body
    assert_select 'a', :html => /Domoway/
  end

  def test_post_contacts_notes_with_search
    @request.session[:user_id] = 1
    compatible_xhr_request :post, :contacts_notes, :search_note => 'Note 1'
    assert_response :success
    assert_match 'note_data', response.body
    assert_select 'table.note_data div.note.content.preview', /Note 1/
    assert_select 'table.note_data div.note.content.preview', { :count => 0, :text => /Note 2/ }
  end

  def test_post_contacts_notes_with_search_in_project
    @request.session[:user_id] = 1
    compatible_xhr_request :post, :contacts_notes, :search_note => 'Note 2', :project_id => 'ecookbook'
    assert_response :success
    assert_match 'note_data', response.body
    assert_select 'table.note_data div.note.content.preview', /Note 2/
  end

  def test_post_create_with_avatar
    image = Redmine::Plugin.find(:redmine_contacts).directory + '/test/fixtures/files/image.jpg'
    attach = Attachment.create!(:file => Rack::Test::UploadedFile.new(image, 'image/jpeg'), :author => User.find(1))

    @request.session[:user_id] = 1
    assert_difference 'Contact.count' do
      compatible_request :post, :create, :project_id => 1,
                                         :attachments => { '0' => { 'filename' => 'image.jpg', 'description' => 'avatar', 'token' => attach.token } },
                                         :contact => { :last_name => 'Testov',
                                                       :middle_name => 'Test',
                                                       :first_name => 'Testovich' }
    end

    assert_redirected_to :controller => 'contacts', :action => 'show', :id => Contact.last.id, :project_id => Contact.last.project
    assert_equal 'Contact', Attachment.last.container_type
    assert_equal Contact.last.id, Attachment.last.container_id

    assert_equal 'image.jpg', Attachment.last.diskfile[/image\.jpg/]
  end

  def test_last_notes_for_contact
    contact = Contact.find(1)
    note = contact.notes.create(:content => 'note for contact', :author_id => 1)
    @request.session[:user_id] = 1
    compatible_request :get, :index
    assert_response :success
    assert_select '.note.content', :text => note.content
  end
end
