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

module RedmineContacts
  module Patches
    module MailerPatch
      def self.included(receiver)
        receiver.extend         ClassMethods
        receiver.send :include, InstanceMethods
        receiver.class_eval do
          unloadable
        end
      end

      module ClassMethods
      end

      module InstanceMethods
        def crm_note_add(_user, note)
          redmine_headers 'Project' => note.source.project.identifier,
                          'X-Notable-Id' => note.source.id,
                          'X-Note-Id' => note.id
          @author = note.author
          message_id note
          recipients = note.source.recipients
          cc = (note.source.respond_to?(:all_watcher_recepients) ? note.source.all_watcher_recepients : note.source.watcher_recipients) - recipients
          @note = note
          @note_url = url_for(:controller => 'notes', :action => 'show', :id => note.id)
          mail :to => recipients,
               :cc => cc,
               :subject => "[#{note.source.project.name}] - #{l(:label_crm_note_for)} #{note.source.name}"
        end

        def crm_contact_add(_user, contact)
          redmine_headers 'Project' => contact.project.identifier,
                          'X-Contact-Id' => contact.id
          @author = contact.author
          message_id contact
          recipients = contact.recipients
          cc = contact.watcher_recipients - recipients
          @contact = contact
          @contact_url = url_for(:controller => 'contacts', :action => 'show', :id => contact.id)
          mail :to => recipients,
               :cc => cc,
               :subject => "[#{contact.project.name} - #{l(:label_contact)} ##{contact.id}] #{contact.name}"
        end
      end
    end
  end
end

unless Mailer.included_modules.include?(RedmineContacts::Patches::MailerPatch)
  Mailer.send(:include, RedmineContacts::Patches::MailerPatch)
end
