-- Keep the hardware read policy separate from write policies so the
-- Supabase advisor does not report duplicate permissive SELECT policies.
drop policy if exists hardware_devices_manage on public.hardware_devices;

create policy hardware_devices_insert
on public.hardware_devices for insert
to authenticated
with check ((select private.hardware_device_authorized(business_id, branch_id, 'hardware.manage')));

create policy hardware_devices_update
on public.hardware_devices for update
to authenticated
using ((select private.hardware_device_authorized(business_id, branch_id, 'hardware.manage')))
with check ((select private.hardware_device_authorized(business_id, branch_id, 'hardware.manage')));

create policy hardware_devices_delete
on public.hardware_devices for delete
to authenticated
using ((select private.hardware_device_authorized(business_id, branch_id, 'hardware.manage')));
