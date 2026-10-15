do $$
declare feed jsonb; context jsonb;
begin
  feed:=private.customer_area_trending(point(0,0));
  assert jsonb_array_length(feed)=3,'one family includes two sizes; unavailable family excluded';
  assert feed->0->>'name'='Test Milk 1 L','two completed orders beat one order of 99 units';
  assert feed->1->>'name'='Test Milk 500 ml','sold-out sibling is retained in exact size picker';
  assert feed->2->>'name'='Test Butter','second family retains popularity order';
  assert feed->0->>'imageKey' like 'test/%','only verified image projection used';
  assert not (feed->0 ? 'popularity') and not (feed->0 ? 'customerId'),'private statistics and actors are not returned';
  assert private.trending_delivery_point('{}'::jsonb) is null,'missing historical address ignored';
  assert private.trending_delivery_point('{"latitude":"bad","longitude":0}'::jsonb) is null,'malformed historical address ignored';
  assert private.trending_delivery_point('{"latitude":91,"longitude":0}'::jsonb) is null,'invalid coordinate range ignored';
  assert private.customer_area_trending(point(5,5))='[]'::jsonb,'outside local order area is empty';
  update dastak_v1.category_types set slug='pharmacy';
  assert private.customer_area_trending(point(0,0))='[]'::jsonb,'controlled products do not bypass their own flow';
  update dastak_v1.category_types set slug='groceries';
  -- Cancelled, old, remote, unlocated and refunded orders cannot increase Milk's score.
  update dastak_v1.orders set delivered_at=now() where id=md5('trend-order3')::uuid;
  feed:=private.customer_area_trending(point(0,0));
  assert feed->0->>'name'='Test Milk 1 L','recency cannot beat distinct order popularity';
  update dastak_v1.sku_images set rights_status='UNCLEARED' where sku_id::text like '%004';
  assert jsonb_array_length(private.customer_area_trending(point(0,0)))=2,'uncleared image product excluded';
  update dastak_v1.merchant_sku_selections set stock_quantity=0 where sku_id::text like '%001';
  assert private.customer_area_trending(point(0,0))='[]'::jsonb,'no available pack excludes the whole family';
  update dastak_v1.merchant_sku_selections set stock_quantity=5 where sku_id::text like '%001';
  perform set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
  context:=dastak_v1_api.customer_area_availability('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd','2026-10-08T00:00:00Z');
  assert context ? 'trendingSkus','existing availability response supplies feed';
  begin perform dastak_v1_api.customer_area_availability('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    '99999999-9999-4999-8999-999999999999','2026-10-08T00:00:00Z');
    raise exception 'another customer address accepted'; exception when insufficient_privilege then null; end;
  begin perform dastak_v1_api.customer_area_availability('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd','2026-10-09T00:00:00Z');
    raise exception 'stale address version accepted'; exception when invalid_parameter_value then null; end;
  assert not has_function_privilege('authenticated','private.customer_area_trending(extensions.geometry)','EXECUTE'),'no raw private ranking access';
end;$$;
