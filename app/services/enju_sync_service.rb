# encoding: utf-8
require 'digest/sha1'
require 'digest/md5'
require 'net/ftp'
require "open3"

module EnjuSyncServices
  class SyncError < StandardError ; end

  module EnjuSyncUtil
    def tag_logger(msg)
      logmsg = "#{$enju_log_head} #{$enju_log_tag} #{Time.now.strftime("%Y-%m-%d %H:%M:%S")} #{msg}"
      Rails.logger.info logmsg
      puts logmsg
    end

    def tag_notifier(msg, c = caller)
      tag_logger(msg)
      ex = SyncError.new(msg)
      ex.set_backtrace(c)
      sync_notifier(ex)
    end

    def sync_notifier(ex)
      ExceptionNotifier::Rake.maybe_deliver_notification ex
    end

    def change_control_file_to_imported(ctl_file_name)
      control_file_status_change(ctl_file_name, "IMP")
    end

    def change_control_file_to_error(ctl_file_name)
      control_file_status_change(ctl_file_name, "ERR")
    end

    def change_control_file_to_success(ctl_file_name)
      control_file_status_change(ctl_file_name, "END")
    end

    def control_file_status_change(control_file_name, status_mark)
      unless /^(.*)\/(\d+)-(\w+)-(\d+)\.ctl$/ =~ control_file_name
        tar_logger "FATAL: ctl_file error (1) #{target_dir}"
        return
      end
      target_dir = $1
      exec_date = $2
      send_stat = $3
      retry_cnt = $4

      #tag_logger "control_file_nam=#{control_file_name} target_dir=#{target_dir}"
      rename_file_rename = File.join(target_dir, "#{exec_date}-#{status_mark}-#{retry_cnt}.ctl")

      tag_logger "rename to #{rename_file_rename}"
      File.rename(control_file_name, rename_file_rename)
    end
  end

  class Sync
    LOGFILE = 'log/sync.log'

    SLAVE_SERVER_DIR = "/var/enjusync"  # 送信先
    RECEIVE_DIR = "/var/enjusync"       # 受信時の取得場所
    PUT_DIR = "/var/enjusync"

    MASTER_SERVER_DIR = "/var/enjusync"
    DUMPFILE_NAME = "enjudump.marshal"
    COMPRESS_FILE_NAME = "dumpfiles.gz"
    STATUSFILE_NAME = "status.marshal"
    STATUS_FILE = "#{MASTER_SERVER_DIR}/work/#{STATUSFILE_NAME}"

    self.extend EnjuSyncUtil

    def self.export(params)
      if params[:STATUS_FILE]
        Dir.glob(Rails.root.join('app/models/**/*.rb')).each { |path| require path }
        status = Marshal.load(File.read(params[:STATUS_FILE]))
        last_event_id = status[:last_event_id]
        unless last_event_id
          fail 'no id in the status file, please specify STATUS_FILE=path/to/previous_file or EXPORT_FROM=N'
        end
      elsif params[:EXPORT_FROM]
        last_event_id = Integer(params[:EXPORT_FROM])
      else
        fail 'please specify STATUS_FILE=path/to/file or EXPORT_FROM=N'
      end

      Rails.application.eager_load!
      Rails::Engine.subclasses.each{|engine| engine.instance.eager_load!}

      unless params[:DUMP_FILE]
        fail 'please specify DUMP_FILE=path/to/file'
      end

      dump = Version.export_for_incremental_synchronization(last_event_id)

      if dump[:versions].empty?
        $stderr.puts "no changes found"

      else
        open(params[:DUMP_FILE], 'w') do |io|
          unless io.flock(File::LOCK_EX|File::LOCK_NB)
            fail "another process is writing to #{params[:DUMP_FILE]}"
          end
          Marshal.dump(dump, io)
        end
      end
    end

    def self.import(params)
      unless params[:DUMP_FILE]
        fail 'please specify DUMP_FILE=path/to/file'
      end

      unless params[:STATUS_FILE]
        fail 'please specify STATUS_FILE=path/to/file'
      end

      status = nil

      open(params[:DUMP_FILE], 'r') do |df|
        unless df.flock(File::LOCK_EX|File::LOCK_NB)
          fail "another process is writing to #{params[:DUMP_FILE]}"
        end

        dump = Marshal.load(File.read(df))

        if dump[:versions].empty?
          $stderr.puts "no changes found"

        else
          open(params[:STATUS_FILE], 'w:binary') do |io|
            unless io.flock(File::LOCK_EX|File::LOCK_NB)
              fail "another process is writing to #{params[:STATUS_FILE]}"
            end
            status = Version.import_for_incremental_synchronization!(dump)
            Marshal.dump(status, io)
          end
        end
      end

      unless status[:success]
        failed_event = status[:failed_event]
        fail "import failed on \"#{failed_event[:event_type]} #{failed_event[:item_type]}\##{failed_event[:item_id]}\" (Version\##{status[:failed_event_id]}): #{status[:exception][:message]} (#{status[:exception][:class].name})"
        endv
      end
    end

    def self.show_status
      ftp_site = SystemConfiguration.get("sync.ftp.site")
      ftp_user = SystemConfiguration.get("sync.ftp.user")
      ftp_password = SystemConfiguration.get("sync.ftp.password")
      puts "Configuration:"
      puts " sync.ftp.site: #{ftp_site} "
      puts " sync.ftp.user: #{ftp_user} "
      puts " sync.ftp.password: #{ftp_password} "
      puts " sync.ftp.directory: #{ftp_directory} "
      puts " sync.master.base_directory: #{master_server_dir} "
      puts " sync.slave.base_directory: #{slave_server_dir} "
      puts "Exception:"
      puts " ExceptionNotifier: #{defined?(ExceptionNotifier) ? 'installed' : 'not installed (please install exception_notification-rake.)'}"
      puts "Version:"
      puts " Version.last.id: #{Version.last.id}"
    end

    def self.ftp_directory
      SystemConfiguration.get("sync.ftp.directory") 
    end

    def self.master_server_dir
      SystemConfiguration.get("sync.master.base_directory") # || MASTER_SERVER_DIR
    end

    def self.slave_server_dir
      SystemConfiguration.get("sync.slave.base_directory") # || MASTER_SERVER_DIR
    end

    def self.get_status_file
      ftp_site, ftp_user, ftp_password, ftp_trans_mode = server_connection

      if ftp_site.blank?
        tag_notifier "FATAL: configuration (sync.ftp.site) is empty."
        tag_logger "FATAL: see config/config.yml"
        return
      end

      if ftp_user.blank? || ftp_password.blank?
        tag_notifier "FATAL: configuration (sync.ftp.user or sync.ftp.password) is empty."
        tag_logger "FATAL: see config/config.yml"
        return
      end

      Net::FTP.open(ftp_site, ftp_user, ftp_password) do |ftp|
        ftp.passive = true

        ftp.chdir(ftp_directory)
        file_list =  ftp.nlst("-R *")
        file_list = file_list.grep(/^\.\/\d*\/\d+.*-IMP-\d+\.ctl/)
        last_control_file_name = file_list.sort.last

        unless last_control_file_name =~ /^\.\/(\d*)\/(\d+.*)-IMP-\d+\.ctl/
          tag_logger "no status file"
          return
        end

        status_file_name = "status.marshal"
        remote_file_name = "./#{$1}/#{status_file_name}"
        local_file_name = File.join(master_server_dir, "work", status_file_name)

        tag_logger "pull: remote_file_name=#{remote_file_name} local_file_name=#{local_file_name}"

        ftp.getbinaryfile(remote_file_name, local_file_name)
      end
    end

    def self.load_control_file(ctl_file_name)
      compressed_file_size = 0
      md5checksum = ""
      lines = 0

      open(ctl_file_name) {|file|
        while l = file.gets
          lines += 1

          case lines
          when 1
            compressed_file_size = l.chomp
          when 2
            md5checksum = l.chomp
          when lines > 2
            break
          end
        end
      }

      if /\D.*/ =~ compressed_file_size
        raise EnjuSyncServices::SyncError("control file compressed_file_size error")
      end

      return compressed_file_size, md5checksum
    end

    def self.build_bucket(bucket_id)
      # init backet
      base_dir = EnjuSyncServices::Sync.master_server_dir
      work_dir = File.join(base_dir, "#{bucket_id}")
      gzip_file_name = COMPRESS_FILE_NAME
      marshal_full_name = File.join(work_dir, DUMPFILE_NAME)
      gzip_full_name = File.join(work_dir, gzip_file_name)
      exec_date = Time.now.strftime("%Y%m%d")

      tag_logger "marshal_full_name=#{marshal_full_name} gzip_full_name=#{gzip_full_name}"

      unless FileTest::exist?(marshal_full_name)
        # marshal ファイルが無い場合、ステータスEND、終了
        ctl_file = File.join(work_dir, "#{exec_date}-END-0.ctl")
        FileUtils.touch(ctl_file, :mtime => Time.now)
        tag_logger("Can not open #{marshal_full_name} (no update)");
        return
      end

      # marshal ファイルをgzで圧縮する。
      Zlib::GzipWriter.open(gzip_full_name, Zlib::BEST_COMPRESSION) do |gz|
        gz.mtime = File.mtime(marshal_full_name)
        gz.orig_name = marshal_full_name
        gz.puts File.open(marshal_full_name, 'rb') {|f| f.read }
      end

      file_size = File.size(gzip_full_name)
      md5sum = Digest::MD5.file(gzip_full_name).to_s

      ctl_file = File.join(work_dir, "#{exec_date}-RDY-0.ctl")

      # ステータスファイルにファイルサイズとmd5チェックサムを記述する。
      File.open(ctl_file, "w") do |io|
        io.puts file_size
        io.puts md5sum
      end

    end

    def self.push_by_ftp(ftp_site, ftp_user, ftp_password, passive_mode, bucket_id, push_target_files)
      ftp_site_base_dir = EnjuSyncServices::Sync.ftp_directory
      bucket_dir = File.join(ftp_site_base_dir, "#{bucket_id}")

      tag_logger "ftp_site:#{ftp_site} ftp_user:#{ftp_user} bucket_id:#{bucket_id}"
      tag_logger "ftp_site_dir: #{bucket_dir} passive_mode=#{passive_mode}"

      Net::FTP.open(ftp_site, ftp_user, ftp_password) do |ftp|
        ftp.passive = true if passive_mode

        if ftp.dir(bucket_dir).empty?
          tag_logger "try mkdir: #{bucket_dir}"
          ftp.mkdir(bucket_dir)
        end

        push_target_files.each do |file_name|
          site_file_name = File.join(bucket_dir, File.basename(file_name))
          tag_logger "push file: slave_server_filename: #{site_file_name}"
          ftp.putbinaryfile(file_name, site_file_name)
        end
      end
    end

    def self.marshal_file_recv
      # opac 側の指定ディレクトリを探査
      basedir = EnjuSyncServices::Sync.slave_server_dir
      glob_string = "#{basedir}/[0-9]*/[0-9]*-RDY-*.ctl"

      tag_logger "setup: recv glob_string=#{glob_string}"

      # 受信可能ファイルを取得( RDY|ERR )
      rdy_ctl_files = Dir.glob(glob_string).sort 
      if rdy_ctl_files.empty?
        # 受信すべきバケットがないので、ログを記録して終了
        tag_logger("receive buckets not exist");
        return
      end 

      rdy_ctl_files.each do |ctl_file_name|
        unless /\w+\/(\d+)-(\w+)-(\d+)\.ctl$/ =~ ctl_file_name
          tag_notifier "FATAL: ctl_file error (1) #{target_dir}"
          return
        end
        exec_date = $1
        send_stat = $2
        retry_cnt = $3

        tag_logger "setup: exec_date=#{exec_date} imp_stat=#{send_stat} retry_cnt=#{retry_cnt}"

        target_dir = File.dirname(ctl_file_name)
        unless /.*\/(\d*)$/ =~ target_dir
          tag_notifier "FATAL: ctl_file error (2) #{target_dir}"
          return
        end

        bucket_id = $1

        # prepare
        compress_marshal_file_name = File.join(target_dir, "#{COMPRESS_FILE_NAME}")
        marshal_file_name = File.join(target_dir, DUMPFILE_NAME)
        status_file_name = File.join(target_dir, STATUSFILE_NAME)

        tag_logger "setup: compress_marshal_file_name=#{compress_marshal_file_name} marshal_file_name=#{marshal_file_name} status_file_name=#{status_file_name}"

        # check
        gzfilesize, md5checksum = load_control_file(ctl_file_name)
        actual_file_size = File.size(compress_marshal_file_name)
        unless actual_file_size == gzfilesize.to_i
          tag_notifier "unmatched file size. #{ctl_file_name} ctl_file_size=#{gzfilesize} actual_size=#{actual_file_size}"
          return
        end

        digest = Digest::MD5.file(compress_marshal_file_name)
        unless digest.hexdigest == md5checksum
          tag_notifier "unmatched checksum. #{ctl_file_name} ctl_file_size=#{md5checksum}"
          return
        end

        # uncompress
        tag_logger "setup: uncompress from #{compress_marshal_file_name}"
        Zlib::GzipReader.open(compress_marshal_file_name) do |gz|
          orig_mtime = gz.mtime || Time.now # gz に時刻があればその時刻をタイムスタンプとして使用する
          File.open(marshal_file_name, "wb") do |f|
            f.print gz.read
          end

          File.utime(orig_mtime, orig_mtime, marshal_file_name)
        end

        # rake enju:sync:import DUMP_FILE=$RecvDir/$rcv_bucket/enjudump.marshal STATUS_FILE=$RecvDir/$rcv_bucket/status.marshal
        tag_logger "import: start"
        import(DUMP_FILE: marshal_file_name, STATUS_FILE: status_file_name)

        tag_logger "import: success. change status"
        change_control_file_to_imported(ctl_file_name)
      end
 
    end

    def self.marshal_file_push(bucket_id)
      basedir = EnjuSyncServices::Sync.master_server_dir
      glob_string = "#{basedir}/[0-9]*/*-{RDY,ERR}-*.ctl"

      ftp_site, ftp_user, ftp_password, ftp_trans_mode = server_connection

      #tag_logger "glob_string=#{glob_string}"

      if ftp_site.blank?
        tag_notifier "FATAL: configuration (sync.ftp.site) is empty."
        tag_logger "FATAL: see config/config.yml"
       return
      end

      if ftp_user.blank? || ftp_password.blank?
        tag_notifier "FATAL: configuration (sync.ftp.user or sync.ftp.password) is empty."
        tag_logger "FATAL: see config/config.yml"
        return
      end

      # compress marsharl file, create control file and write checksum
      build_bucket(bucket_id)

      # 送信可能ファイルを取得( RDY|ERR )
      rdy_ctl_files = Dir.glob(glob_string).sort 
      if rdy_ctl_files.empty?
        # 送信すべきバケットがないので、ログを記録して終了
        tag_logger("sending buckets not exist");
        return
      end

      rdy_ctl_files.each do |ctl_file_name|
        unless /\w+\/(\d+)-(\w+)-(\d+)\.ctl$/ =~ ctl_file_name
          tag_notifier "FATAL: ctl_file error (1) #{target_dir}"
          return
        end
        exec_date = $1
        send_stat = $2
        retry_cnt = $3

        tag_logger "exec_date=#{exec_date} send_stat=#{send_stat} retry_cnt=#{retry_cnt}"

        target_dir = File.dirname(ctl_file_name)
        unless /.*\/(\d*)$/ =~ target_dir
          tag_notifier "FATAL: ctl_file error (2) target_dir=#{target_dir}"
          return
        end

        bucket_id = $1

        unless send_stat == "RDY"
          tag_logger "skip: status=#{send_stat} ctl_fil_name=#{ctl_file_name}"
          next
        end

        target_dir_s = File.join(target_dir, "#{COMPRESS_FILE_NAME}")
        push_target_files = Dir.glob(target_dir_s).sort 
        push_target_files << "#{ctl_file_name}"

        push_by_ftp(ftp_site, ftp_user, ftp_password, ftp_trans_mode, bucket_id, push_target_files)

        change_control_file_to_success(ctl_file_name)
      end
    end

    def self.server_connection
      ftp_site = SystemConfiguration.get("sync.ftp.site")
      ftp_user = SystemConfiguration.get("sync.ftp.user")
      ftp_password = SystemConfiguration.get("sync.ftp.password")
      ftp_trans_mode = SystemConfiguration.get("sync.ftp.trans_mode_passive") || true
      return ftp_site, ftp_user, ftp_password, ftp_trans_mode
    end
 end
end
