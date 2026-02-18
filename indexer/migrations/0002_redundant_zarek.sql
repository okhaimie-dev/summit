DROP TABLE IF EXISTS "diplomacy_groups" CASCADE;--> statement-breakpoint
DROP TABLE IF EXISTS "skull_events" CASCADE;--> statement-breakpoint
DROP INDEX IF EXISTS "corpse_events_block_tx_event_idx";--> statement-breakpoint
ALTER TABLE "battles" ADD COLUMN IF NOT EXISTS "tier" smallint NOT NULL DEFAULT 1;--> statement-breakpoint
ALTER TABLE "beast_data" ADD COLUMN IF NOT EXISTS "last_killed_by" bigint NOT NULL DEFAULT 0;--> statement-breakpoint
ALTER TABLE "beast_stats" ADD COLUMN IF NOT EXISTS "captured_summit" smallint NOT NULL DEFAULT 0;--> statement-breakpoint
ALTER TABLE "beast_stats" ADD COLUMN IF NOT EXISTS "used_revival_potion" smallint NOT NULL DEFAULT 0;--> statement-breakpoint
ALTER TABLE "beast_stats" ADD COLUMN IF NOT EXISTS "used_attack_potion" smallint NOT NULL DEFAULT 0;--> statement-breakpoint
ALTER TABLE "beast_stats" ADD COLUMN IF NOT EXISTS "max_attack_streak" smallint NOT NULL DEFAULT 0;--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "quest_rewards_claimed_beast_token_id_idx" ON "quest_rewards_claimed" USING btree ("beast_token_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "skulls_claimed_skulls_idx" ON "skulls_claimed" USING btree ("skulls" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "beast_owners_token_id_idx" ON "beast_owners" USING btree ("token_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "beast_stats_diplomacy_token_idx" ON "beast_stats" USING btree ("token_id") WHERE diplomacy > 0;--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "corpse_events_block_tx_event_adv_idx" ON "corpse_events" USING btree ("block_number","transaction_hash","event_index","adventurer_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "summit_log_sub_category_idx" ON "summit_log" USING btree ("sub_category");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "summit_log_category_order_idx" ON "summit_log" USING btree ("category","block_number" DESC NULLS LAST,"event_index" DESC NULLS LAST);--> statement-breakpoint
ALTER TABLE "beast_stats" DROP COLUMN IF EXISTS "has_claimed_potions";