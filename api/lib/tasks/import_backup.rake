require 'zip'

namespace :import do
    desc "Import data from backup ZIP file"
    task backup: :environment do
      class Importer
        def initialize(zip_path)
          @zip_path = zip_path
          @imported_users = {}
          @imported_channels = {}
        end
  
        private
  
        def import_users(zip)
          puts "Mapping users..."
          users_data = JSON.parse(zip.read("users.json"))
          
          users_data.each do |user_data|
            user = User.find_by!(email: user_data["email"])
            @imported_users[user_data["id"]] = user
            puts "Mapped #{user_data['email']} to existing user #{user.id}"
          end
          
          puts "Mapped #{@imported_users.size} users"
        end
        
        private
  
        def import_users(zip)
          puts "Importin g users..."
          users_data = JSON.parse(zip.read("users.json"))
          
          users_data.each do |user_data|
            user = User.find_or_create_by!(public_id: user_data["id"]) do |u|
              u.username = user_data["username"]
              u.email = user_data["email"]
              u.name = user_data["display_name"]
              u.created_at = user_data["created_at"]
              # You might want to set a default password or handle this differently
              u.password = "thesamepassword111111"
            end
            
            @imported_users[user.public_id] = user
          end
          
          puts "Imported #{@imported_users.size} users"
        end
  
        def import_channels(zip)
          puts "Importing channels..."
          
          zip.glob("channels/*/channel.json") do |entry|
            channel_data = JSON.parse(entry.get_input_stream.read)
            channel_id = entry.name.split('/')[1] # Get ID from path
            
            imported_channel = MessageThread.find_or_create_by!(public_id: channel_id) do |ch|
              ch.name = channel_data["name"]
              ch.private = channel_data["private"]
              ch.created_at = channel_data["created_at"]
              ch.description = channel_data["description"]
              ch.accessory = channel_data["accessory"]
              ch.archived = channel_data["archived"] || false
            end
  
            # Add channel members
            channel_data["members"].each do |member_data|
              user = @imported_users[member_data["id"]]
              next unless user
  
              # Create organization membership if needed
              org_member = OrganizationMembership.find_or_create_by!(
                user: user,
                organization: imported_channel.organization
              ) do |om|
                om.role = member_data["role"]
              end
  
              # Add to channel
              MessageThreadMembership.find_or_create_by!(
                message_thread: imported_channel,
                organization_membership: org_member
              )
            end
            
            @imported_channels[channel_id] = imported_channel
          end
          
          puts "Imported #{@imported_channels.size} channels"
        end
  
        def import_content(zip)
          import_posts(zip)
          import_notes(zip)
          import_calls(zip)
        end
  
        def import_posts(zip)
          puts "Importing posts..."
          imported = 0
  
          zip.glob("channels/*/posts/*/post.json") do |entry|
            post_data = JSON.parse(entry.get_input_stream.read)
            path_parts = entry.name.split('/')
            channel_id = path_parts[1]
            post_id = path_parts[3]
            channel = @imported_channels[channel_id]
            
            next unless channel
            
            post = Post.find_or_create_by!(public_id: post_data["id"]) do |p|
              p.title = post_data["title"]
              p.description = post_data["description"]
              p.created_at = post_data["created_at"]
              p.member = find_org_member(post_data["author"]["id"], channel.organization)
              p.organization = channel.organization
              p.project = channel.project
            end
  
            import_comments(post, post_data["comments"])
            import_attachments_from_zip(zip, post, "channels/#{channel_id}/posts/#{post_id}")
            
            imported += 1
          end
          
          puts "Imported #{imported} posts"
        end
  
        def import_notes(zip)
          puts "Importing notes..."
          imported = 0
  
          zip.glob("channels/*/docs/*/note.json") do |entry|
            note_data = JSON.parse(entry.get_input_stream.read)
            path_parts = entry.name.split('/')
            channel_id = path_parts[1]
            note_id = path_parts[3]
            channel = @imported_channels[channel_id]
            
            next unless channel
            
            note = Note.find_or_create_by!(public_id: note_data["id"]) do |n|
              n.title = note_data["title"]
              n.description = note_data["description"]
              n.created_at = note_data["created_at"]
              n.member = find_org_member(note_data["author"]["id"], channel.organization)
              n.project = channel.project
            end
  
            import_comments(note, note_data["comments"])
            import_attachments_from_zip(zip, note, "channels/#{channel_id}/docs/#{note_id}")
            
            imported += 1
          end
          
          puts "Imported #{imported} notes"
        end
  
        def import_calls(zip)
          puts "Importing calls..."
          imported = 0
  
          zip.glob("channels/*/calls/*/call.json") do |entry|
            call_data = JSON.parse(entry.get_input_stream.read)
            path_parts = entry.name.split('/')
            channel_id = path_parts[1]
            call_id = path_parts[3]
            channel = @imported_channels[channel_id]
            
            next unless channel
  
            room = CallRoom.find_or_create_by!(
              organization: channel.organization,
              subject: channel
            )
  
            call = Call.find_or_create_by!(public_id: call_data["id"]) do |c|
              c.title = call_data["title"]
              c.summary = call_data["summary"]
              c.created_at = call_data["created_at"]
              c.duration = call_data["duration"]
              c.room = room
              c.project = channel.project
            end
  
            call_data["peers"].each do |peer|
              member = find_org_member(peer["organization_membership_id"], channel.organization)
              next unless member
  
              CallPeer.find_or_create_by!(
                call: call,
                organization_membership: member
              )
            end
  
            import_recordings_from_zip(zip, call, "channels/#{channel_id}/calls/#{call_id}")
            imported += 1
          end
          
          puts "Imported #{imported} calls"
        end
  
        private
  
        def find_org_member(user_id, organization)
          user = @imported_users[user_id]
          return unless user
  
          OrganizationMembership.find_or_create_by!(
            user: user,
            organization: organization
          )
        end
  
        def import_comments(subject, comments_data)
          return unless comments_data
  
          comments_data.each do |comment_data|
            comment = Comment.find_or_create_by!(public_id: comment_data["id"]) do |c|
              c.body = comment_data["body"]
              c.created_at = comment_data["created_at"]
              c.member = find_org_member(comment_data["author"]["id"], subject.organization)
              c.subject = subject
              c.resolved_at = comment_data["resolved_at"]
              c.resolved_by = comment_data["resolved_by"] ? find_org_member(comment_data["resolved_by"]["id"], subject.organization) : nil
            end
  
            import_comments(comment, comment_data["replies"]) if comment_data["replies"].present?
          end
        end
  
        def import_attachments_from_zip(zip, subject, base_path)
          zip.glob("#{base_path}/*").each do |entry|
            next if entry.name.end_with?('.json')
            next if entry.directory?
            
            filename = File.basename(entry.name)
            
            Attachment.find_or_create_by!(
              subject: subject,
              filename: filename
            ) do |a|
              temp_file = Tempfile.new(filename)
              temp_file.binmode
              temp_file.write(entry.get_input_stream.read)
              temp_file.rewind
              
              a.file.attach(io: temp_file, filename: filename)
              temp_file.close
              temp_file.unlink
            end
          end
        end
  
        def import_recordings_from_zip(zip, call, base_path)
          zip.glob("#{base_path}/recordings/*.mp4").each do |entry|
            filename = File.basename(entry.name)
            recording = CallRecording.find_or_create_by!(
              call: call,
              filename: filename
            ) do |r|
              temp_file = Tempfile.new(filename)
              temp_file.binmode
              temp_file.write(entry.get_input_stream.read)
              temp_file.rewind
              
              r.file.attach(io: temp_file, filename: filename)
              temp_file.close
              temp_file.unlink
            end
  
            # Import transcription if it exists
            vtt_name = "#{filename.chomp('.mp4')}_transcription.vtt"
            vtt_entry = zip.glob("#{base_path}/recordings/#{vtt_name}").first
            if vtt_entry
              temp_file = Tempfile.new(vtt_name)
              temp_file.binmode
              temp_file.write(vtt_entry.get_input_stream.read)
              temp_file.rewind
              
              recording.transcription.attach(io: temp_file, filename: vtt_name)
              temp_file.close
              temp_file.unlink
            end
          end
        end
      end
  
      zip_path = ENV['BACKUP_PATH'] || Rails.root.join('tmp', 'backup.zip')
      Importer.new(zip_path).import
    end
  end