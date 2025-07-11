
-- Create documents table only if it doesn't exist
CREATE TABLE IF NOT EXISTS documents (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  filename text NOT NULL,
  file_path text NOT NULL,
  signed_file_path text,
  sender_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_email text,
  signature_areas jsonb,
  public_link text UNIQUE,
  status text DEFAULT 'pending_setup' CHECK (status IN ('pending_setup', 'sent', 'signed')),
  created_at timestamp with time zone DEFAULT now(),
  signed_at timestamp with time zone
);

-- Create indexes for better performance (only if they don't exist)
CREATE INDEX IF NOT EXISTS documents_sender_id_idx ON documents(sender_id);
CREATE INDEX IF NOT EXISTS documents_public_link_idx ON documents(public_link);
CREATE INDEX IF NOT EXISTS documents_status_idx ON documents(status);

-- Enable Row Level Security
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist to avoid conflicts
DROP POLICY IF EXISTS "Users can view their own documents" ON documents;
DROP POLICY IF EXISTS "Users can insert their own documents" ON documents;
DROP POLICY IF EXISTS "Users can update their own documents" ON documents;
DROP POLICY IF EXISTS "Public access to documents with valid link" ON documents;
DROP POLICY IF EXISTS "Public update for signing documents" ON documents;
DROP POLICY IF EXISTS "Delete own documents" ON documents;

-- Create policies for documents table
CREATE POLICY "Users can view their own documents" ON documents
  FOR SELECT USING (auth.uid() = sender_id);

CREATE POLICY "Users can insert their own documents" ON documents
  FOR INSERT WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "Users can update their own documents" ON documents
  FOR UPDATE USING (auth.uid() = sender_id);

CREATE POLICY "Public access to documents with valid link" ON documents
  FOR SELECT USING (public_link IS NOT NULL AND public_link != '');

CREATE POLICY "Public update for signing documents" ON documents
  FOR UPDATE USING (public_link IS NOT NULL AND public_link != '' AND status = 'sent');

CREATE POLICY "Delete own documents" ON documents
  FOR DELETE USING (auth.uid() = sender_id);

-- Create storage bucket for documents (only if it doesn't exist)
INSERT INTO storage.buckets (id, name, public) 
VALUES ('documents', 'documents', false)
ON CONFLICT (id) DO NOTHING;

-- Drop existing storage policies if they exist to avoid conflicts
DROP POLICY IF EXISTS "Authenticated users can upload documents" ON storage.objects;
DROP POLICY IF EXISTS "Users can view their own document files" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own document files" ON storage.objects;

-- Create storage policies
CREATE POLICY "Authenticated users can upload documents" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'documents' AND auth.role() = 'authenticated');

CREATE POLICY "Users can view their own document files" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'documents' AND
    EXISTS (
      SELECT 1 FROM public.documents d
      WHERE (d.file_path = name OR d.signed_file_path = name) AND d.sender_id = auth.uid()
    )
  );

-- NEW, MORE ROBUST DELETE POLICY
CREATE POLICY "Users can delete their own document files" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'documents' AND
    EXISTS (
      SELECT 1 FROM public.documents d
      WHERE (d.file_path = name OR d.signed_file_path = name) AND d.sender_id = auth.uid()
    )
  );
