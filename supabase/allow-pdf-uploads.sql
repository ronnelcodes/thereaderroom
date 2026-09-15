-- The Reader Room: allow DOCX, TXT, and PDF manuscript uploads.
-- Run this once in Supabase SQL Editor for an existing project.

update storage.buckets
set file_size_limit = 20971520,
    allowed_mime_types = array[
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'text/plain',
      'application/pdf'
    ]
where id = 'manuscripts';
