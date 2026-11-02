-- Cover the composite branch foreign key in the same column order used by
-- PostgreSQL's FK checks and Supabase's performance advisor.

create index held_pos_carts_branch_business_fk_idx
  on public.held_pos_carts(branch_id, business_id);
