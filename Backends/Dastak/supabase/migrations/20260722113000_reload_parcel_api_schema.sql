-- Make the newly added parcel RPCs visible to PostgREST immediately.
notify pgrst, 'reload schema';
