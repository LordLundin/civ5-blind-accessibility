-- DiploOverview bridge. The three tab panels (DiploRelationships,
-- DiploCurrentDeals, DiploGlobalRelationships) are embedded LuaContexts
-- inside DiploOverview.xml; each runs in its own Context env, so the base
-- tab-switch globals OnRelations / OnDeals / OnGlobal -- defined here in
-- DiploOverview's Context -- aren't directly callable from the children.
--
-- This bridge publishes references to those functions on
-- civvaccess_shared so the per-panel accessibility wrappers can route
-- Tab / Shift+Tab to the right base fn, which flips the sighted panel
-- and triggers the ShowHide cycle that pops the current wrapper's menu
-- and pushes the sibling's.

civvaccess_shared.DiploOverview = civvaccess_shared.DiploOverview or {}
civvaccess_shared.DiploOverview.showRelations = OnRelations
civvaccess_shared.DiploOverview.showDeals = OnDeals
civvaccess_shared.DiploOverview.showGlobal = OnGlobal
