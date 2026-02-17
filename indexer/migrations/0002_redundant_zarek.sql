CREATE TABLE "quest_rewards_claimed" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"beast_token_id" integer NOT NULL,
	"amount" smallint NOT NULL,
	"updated_at" timestamp DEFAULT now(),
	CONSTRAINT "quest_rewards_claimed_beast_token_id_unique" UNIQUE("beast_token_id")
);
--> statement-breakpoint
CREATE TABLE "skulls_claimed" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"beast_token_id" integer NOT NULL,
	"skulls" bigint NOT NULL,
	"updated_at" timestamp DEFAULT now(),
	CONSTRAINT "skulls_claimed_beast_token_id_unique" UNIQUE("beast_token_id")
);
--> statement-breakpoint
ALTER TABLE "diplomacy_groups" DISABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "skull_events" DISABLE ROW LEVEL SECURITY;--> statement-breakpoint
DROP TABLE "diplomacy_groups" CASCADE;--> statement-breakpoint
DROP TABLE "skull_events" CASCADE;--> statement-breakpoint
DROP INDEX "corpse_events_block_tx_event_idx";--> statement-breakpoint
ALTER TABLE "battles" ADD COLUMN "tier" smallint NOT NULL;--> statement-breakpoint
ALTER TABLE "beast_data" ADD COLUMN "last_killed_by" bigint NOT NULL;--> statement-breakpoint
ALTER TABLE "beast_stats" ADD COLUMN "captured_summit" smallint NOT NULL;--> statement-breakpoint
ALTER TABLE "beast_stats" ADD COLUMN "used_revival_potion" smallint NOT NULL;--> statement-breakpoint
ALTER TABLE "beast_stats" ADD COLUMN "used_attack_potion" smallint NOT NULL;--> statement-breakpoint
ALTER TABLE "beast_stats" ADD COLUMN "max_attack_streak" smallint NOT NULL;--> statement-breakpoint
CREATE INDEX "quest_rewards_claimed_beast_token_id_idx" ON "quest_rewards_claimed" USING btree ("beast_token_id");--> statement-breakpoint
CREATE INDEX "skulls_claimed_skulls_idx" ON "skulls_claimed" USING btree ("skulls" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "beast_owners_token_id_idx" ON "beast_owners" USING btree ("token_id");--> statement-breakpoint
CREATE INDEX "beast_stats_diplomacy_token_idx" ON "beast_stats" USING btree ("token_id") WHERE diplomacy > 0;--> statement-breakpoint
CREATE UNIQUE INDEX "corpse_events_block_tx_event_adv_idx" ON "corpse_events" USING btree ("block_number","transaction_hash","event_index","adventurer_id");--> statement-breakpoint
CREATE INDEX "summit_log_sub_category_idx" ON "summit_log" USING btree ("sub_category");--> statement-breakpoint
CREATE INDEX "summit_log_category_order_idx" ON "summit_log" USING btree ("category","block_number" DESC NULLS LAST,"event_index" DESC NULLS LAST);--> statement-breakpoint
ALTER TABLE "beast_stats" DROP COLUMN "has_claimed_potions";