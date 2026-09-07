-- Commit enum additions before the runtime migration uses them.
alter type dastak_v1.order_status add value if not exists 'CANCELLED';
alter type dastak_v1.order_line_status add value if not exists 'CANCELLED';
alter type dastak_v1.package_status add value if not exists 'CANCELLED';
