-- Enum values are committed separately so the following structural migration
-- can safely use them in constraints and functions on every supported
-- PostgreSQL version.

alter type dastak_v1.merchant_opportunity_status
  add value if not exists 'PROVISIONALLY_ACCEPTED' after 'OFFERED';

alter type dastak_v1.merchant_opportunity_status
  add value if not exists 'RELEASED' after 'SELECTED';
