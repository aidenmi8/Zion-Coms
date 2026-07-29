-- Zion Watch approval delegation and direct-mention push matching.
--
-- Approval commands consume pending rows transactionally. These columns retain
-- the actionable request event and the terminal delegation target without ever
-- storing the plaintext approval token.
ALTER TYPE approval_status ADD VALUE IF NOT EXISTS 'delegated';

ALTER TABLE workflow_approvals
    ADD COLUMN delegated_to_pubkey BYTEA,
    ADD COLUMN delegated_at TIMESTAMPTZ,
    ADD COLUMN request_event_id BYTEA,
    ADD CONSTRAINT workflow_approvals_delegated_pubkey_length
        CHECK (delegated_to_pubkey IS NULL OR octet_length(delegated_to_pubkey) = 32),
    ADD CONSTRAINT workflow_approvals_request_event_id_length
        CHECK (request_event_id IS NULL OR octet_length(request_event_id) = 32);

CREATE INDEX idx_workflow_approvals_pending_approver
    ON workflow_approvals (community_id, approver_spec, expires_at)
    WHERE status = 'pending';

-- Replace the gated matcher trigger so direct mention kind 40002 participates
-- in the same lost-wake ordering protocol as the existing push kinds.
CREATE OR REPLACE FUNCTION enqueue_push_match_job() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    -- Keep this allowlist identical to the relay's validated NIP-PL descriptor.
    IF NEW.kind IN (7, 9, 1059, 40002, 40007, 46010) THEN
        PERFORM pg_advisory_xact_lock_shared(
            hashtextextended('buzz_push_gate:' || NEW.community_id::text, 0));
        IF EXISTS (
            SELECT 1 FROM push_leases
            WHERE community_id = NEW.community_id
              AND active
              AND endpoint_enabled
              AND expires_at > EXTRACT(EPOCH FROM now())::bigint
        ) THEN
            INSERT INTO push_match_queue (community_id, event_id)
            VALUES (NEW.community_id, NEW.id)
            ON CONFLICT DO NOTHING;
        END IF;
    END IF;
    RETURN NEW;
END
$$;
