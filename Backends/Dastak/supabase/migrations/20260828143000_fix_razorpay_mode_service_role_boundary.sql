set check_function_bodies = on;

-- These mode-isolated provider wrappers are callable only by service_role and
-- delegate customer/ownership validation to the existing SECURITY DEFINER V1
-- commands. They also inspect protected provider-mode snapshots themselves,
-- so they must execute with their owner privileges rather than requiring broad
-- direct table grants for service_role.
alter function public.dastak_v1_prepare_razorpay_checkout_mode(
  uuid, uuid, text, text
) security definer;

alter function public.dastak_v1_attach_razorpay_order_mode(
  uuid, uuid, text, bigint, text, text
) security definer;

alter function public.dastak_v1_custom_checkout_completion_context_mode(
  uuid, uuid, uuid, text
) security definer;

alter function public.dastak_v1_record_custom_checkout_completion_mode(
  uuid, uuid, uuid, text, text, text, text, text, text
) security definer;

alter function public.dastak_v1_prepare_razorpay_refund_mode(
  uuid, uuid, text, text
) security definer;

alter function public.dastak_v1_attach_razorpay_refund_mode(
  uuid, uuid, text, bigint, text
) security definer;

alter function public.dastak_v1_record_razorpay_event_mode(
  text, text, text, text, text, bigint, timestamptz, text, text
) security definer;
