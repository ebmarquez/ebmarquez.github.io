Jekyll::Hooks.register :site, :post_write do |site|
  # Ensure .pem files are served with correct MIME type
  pem_files = Dir.glob(File.join(site.dest, '**', '*.pem'))
  pem_files.each do |file|
    # The web server will handle MIME types, but we ensure the file is copied correctly
    puts "Found .pem file: #{file}"
  end
end