SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: audit_logs_immutable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_logs_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN RAISE EXCEPTION 'audit_logs is append-only (% blocked)', TG_OP; END $$;


--
-- Name: auth_lookup_accounts(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_lookup_accounts(p_provider text, p_subject text, p_email text) RETURNS TABLE(account_id uuid, tenant_id uuid, status text, bound boolean, org_name text, org_region text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'pg_temp'
    AS $$
    SELECT a.id, a.tenant_id, a.status::text, true, o.name, o.region
    FROM public.accounts a
    JOIN public.organizations o ON o.id = a.tenant_id
    WHERE a.idp_provider = p_provider AND a.idp_subject = p_subject
    UNION
    SELECT a.id, a.tenant_id, a.status::text, false, o.name, o.region
    FROM public.accounts a
    JOIN public.organizations o ON o.id = a.tenant_id
    WHERE a.idp_subject IS NULL
      AND a.status = 'active'
      AND p_email IS NOT NULL AND p_email <> ''
      AND lower(a.email) = lower(p_email);
  $$;


--
-- Name: auth_lookup_invitation(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_lookup_invitation(p_token_digest text) RETURNS TABLE(invitation_id uuid, tenant_id uuid)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'pg_temp'
    AS $$
    SELECT i.id, i.tenant_id
    FROM public.invitations i
    WHERE i.token_digest = p_token_digest
      AND i.accepted_at IS NULL
      AND i.revoked_at IS NULL
      AND i.expires_at > now();
  $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    email character varying NOT NULL,
    display_name character varying,
    status character varying DEFAULT 'invited'::character varying NOT NULL,
    is_cooa_staff boolean DEFAULT false NOT NULL,
    token_version integer DEFAULT 0 NOT NULL,
    idp_subject character varying,
    region character varying,
    deleted_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint,
    idp_provider character varying,
    avatar_color character varying,
    job_title character varying,
    CONSTRAINT accounts_status_check CHECK (((status)::text = ANY ((ARRAY['invited'::character varying, 'active'::character varying, 'suspended'::character varying, 'deprovisioned'::character varying])::text[])))
);

ALTER TABLE ONLY public.accounts FORCE ROW LEVEL SECURITY;


--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id bigint NOT NULL,
    blob_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying NOT NULL,
    record_id bigint NOT NULL,
    record_type character varying NOT NULL
);


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_attachments_id_seq OWNED BY public.active_storage_attachments.id;


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id bigint NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    content_type character varying,
    created_at timestamp(6) without time zone NOT NULL,
    filename character varying NOT NULL,
    key character varying NOT NULL,
    metadata text,
    service_name character varying NOT NULL
);


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_blobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_blobs_id_seq OWNED BY public.active_storage_blobs.id;


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id bigint NOT NULL,
    blob_id bigint NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_variant_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_variant_records_id_seq OWNED BY public.active_storage_variant_records.id;


--
-- Name: ad_risk_expressions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ad_risk_expressions (
    id bigint NOT NULL,
    citation character varying,
    classification_trigger text,
    country character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    fact_id character varying,
    keyword_ko character varying,
    keyword_native character varying,
    risk_level character varying,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ad_risk_expressions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ad_risk_expressions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ad_risk_expressions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ad_risk_expressions_id_seq OWNED BY public.ad_risk_expressions.id;


--
-- Name: annotation_comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.annotation_comments (
    id bigint NOT NULL,
    annotation_id integer NOT NULL,
    attachment_name character varying,
    author_id integer NOT NULL,
    body text,
    created_at timestamp(6) without time zone NOT NULL,
    parent_id integer,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id uuid NOT NULL
);

ALTER TABLE ONLY public.annotation_comments FORCE ROW LEVEL SECURITY;


--
-- Name: annotation_comments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.annotation_comments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: annotation_comments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.annotation_comments_id_seq OWNED BY public.annotation_comments.id;


--
-- Name: annotations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.annotations (
    id bigint NOT NULL,
    after_text character varying,
    before_text character varying,
    box_h double precision,
    box_w double precision,
    box_x double precision,
    box_y double precision,
    category character varying,
    component_version_id integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    created_by_id integer,
    "position" integer DEFAULT 0,
    resolved_at timestamp(6) without time zone,
    resolved_by_id integer,
    resolved_in_version_id integer,
    seq integer,
    status character varying DEFAULT 'open'::character varying,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id uuid NOT NULL
);

ALTER TABLE ONLY public.annotations FORCE ROW LEVEL SECURITY;


--
-- Name: annotations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.annotations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: annotations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.annotations_id_seq OWNED BY public.annotations.id;


--
-- Name: approval_request_reviewers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_request_reviewers (
    id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    approval_request_id bigint NOT NULL,
    reviewer_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.approval_request_reviewers FORCE ROW LEVEL SECURITY;


--
-- Name: approval_request_reviewers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.approval_request_reviewers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: approval_request_reviewers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.approval_request_reviewers_id_seq OWNED BY public.approval_request_reviewers.id;


--
-- Name: approval_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_requests (
    id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    submitter_id bigint NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    reviewed_artifact_digest character varying NOT NULL,
    reviewed_content_snapshot_hash character varying NOT NULL,
    requested_at timestamp(6) without time zone NOT NULL,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    component_version_id bigint NOT NULL,
    due_at timestamp with time zone
);

ALTER TABLE ONLY public.approval_requests FORCE ROW LEVEL SECURITY;


--
-- Name: approval_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.approval_requests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: approval_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.approval_requests_id_seq OWNED BY public.approval_requests.id;


--
-- Name: approval_steps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_steps (
    id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    approval_request_id bigint NOT NULL,
    approver_id bigint NOT NULL,
    decision character varying NOT NULL,
    reason text,
    acted_at timestamp(6) without time zone NOT NULL,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.approval_steps FORCE ROW LEVEL SECURITY;


--
-- Name: approval_steps_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.approval_steps_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: approval_steps_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.approval_steps_id_seq OWNED BY public.approval_steps.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    region character varying,
    actor_id bigint,
    actor_account_id uuid,
    action character varying NOT NULL,
    resource_type character varying NOT NULL,
    resource_id bigint,
    outcome character varying NOT NULL,
    denial_reason character varying,
    policy_version integer DEFAULT 0 NOT NULL,
    before jsonb,
    after jsonb,
    source_ip inet,
    request_id character varying,
    user_agent character varying,
    tenant_seq bigint NOT NULL,
    prev_chain_hash character varying,
    chain_hash character varying NOT NULL,
    ts timestamp(6) without time zone DEFAULT now() NOT NULL,
    on_behalf_of_account_id uuid,
    impersonation_session_id bigint,
    impersonation_context jsonb
);

ALTER TABLE ONLY public.audit_logs FORCE ROW LEVEL SECURITY;


--
-- Name: audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.audit_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.audit_logs_id_seq OWNED BY public.audit_logs.id;


--
-- Name: component_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.component_versions (
    id bigint NOT NULL,
    change_reason character varying,
    component_id integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    created_by_id integer,
    current boolean DEFAULT false,
    image_name character varying,
    label character varying,
    updated_at timestamp(6) without time zone NOT NULL,
    version_number integer NOT NULL,
    tenant_id uuid NOT NULL
);

ALTER TABLE ONLY public.component_versions FORCE ROW LEVEL SECURITY;


--
-- Name: component_versions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.component_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: component_versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.component_versions_id_seq OWNED BY public.component_versions.id;


--
-- Name: components; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.components (
    id bigint NOT NULL,
    component_type character varying,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying,
    "position" integer DEFAULT 0,
    product_id integer NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id uuid NOT NULL
);

ALTER TABLE ONLY public.components FORCE ROW LEVEL SECURITY;


--
-- Name: components_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.components_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: components_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.components_id_seq OWNED BY public.components.id;


--
-- Name: ingredient_limits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingredient_limits (
    id bigint NOT NULL,
    cas character varying,
    category character varying,
    citation character varying,
    country character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    fact_id character varying,
    inci_canonical character varying NOT NULL,
    max_pct numeric(8,4),
    max_pct_unit character varying,
    restriction_type character varying,
    source_url character varying,
    status character varying,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ingredient_limits_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ingredient_limits_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ingredient_limits_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ingredient_limits_id_seq OWNED BY public.ingredient_limits.id;


--
-- Name: ingredients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingredients (
    id bigint NOT NULL,
    cas character varying,
    component_version_id integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    declared_pct numeric(6,2),
    inci_canonical character varying,
    inci_name character varying,
    "position" integer DEFAULT 0,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id uuid NOT NULL
);

ALTER TABLE ONLY public.ingredients FORCE ROW LEVEL SECURITY;


--
-- Name: ingredients_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ingredients_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ingredients_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ingredients_id_seq OWNED BY public.ingredients.id;


--
-- Name: invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invitations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    email character varying NOT NULL,
    role_key character varying NOT NULL,
    token_digest character varying NOT NULL,
    invited_by_account_id uuid NOT NULL,
    accepted_account_id uuid,
    expires_at timestamp(6) without time zone NOT NULL,
    accepted_at timestamp(6) without time zone,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    scope_type character varying DEFAULT 'tenant'::character varying NOT NULL,
    scope_product_id bigint,
    scope_component_id bigint,
    scope_workspace_id bigint,
    CONSTRAINT inv_scope_coherence CHECK (((((scope_type)::text = 'tenant'::text) AND (scope_workspace_id IS NULL) AND (scope_product_id IS NULL) AND (scope_component_id IS NULL)) OR (((scope_type)::text = 'workspace'::text) AND (scope_workspace_id IS NOT NULL) AND (scope_product_id IS NULL) AND (scope_component_id IS NULL)) OR (((scope_type)::text = 'product'::text) AND (scope_workspace_id IS NULL) AND (scope_product_id IS NOT NULL) AND (scope_component_id IS NULL)) OR (((scope_type)::text = 'component'::text) AND (scope_workspace_id IS NULL) AND (scope_product_id IS NULL) AND (scope_component_id IS NOT NULL))))
);

ALTER TABLE ONLY public.invitations FORCE ROW LEVEL SECURITY;


--
-- Name: label_requirements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.label_requirements (
    id bigint NOT NULL,
    citation character varying,
    country character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    fact_id character varying,
    item character varying,
    location character varying,
    match_keyword character varying,
    parent_law character varying,
    required_text text,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: label_requirements_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.label_requirements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: label_requirements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.label_requirements_id_seq OWNED BY public.label_requirements.id;


--
-- Name: label_texts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.label_texts (
    id bigint NOT NULL,
    component_version_id integer NOT NULL,
    content text,
    country character varying,
    created_at timestamp(6) without time zone NOT NULL,
    language character varying,
    text_type character varying DEFAULT 'label'::character varying,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id uuid NOT NULL
);

ALTER TABLE ONLY public.label_texts FORCE ROW LEVEL SECURITY;


--
-- Name: label_texts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.label_texts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: label_texts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.label_texts_id_seq OWNED BY public.label_texts.id;


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    region character varying NOT NULL,
    billing_tier character varying DEFAULT 'starter'::character varying NOT NULL,
    impersonation_opt_out boolean DEFAULT false NOT NULL,
    deleted_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT organizations_billing_tier_check CHECK (((billing_tier)::text = ANY ((ARRAY['starter'::character varying, 'professional'::character varying, 'enterprise'::character varying, 'custom'::character varying])::text[]))),
    CONSTRAINT organizations_region_check CHECK (((region)::text = ANY ((ARRAY['JP'::character varying, 'CN'::character varying, 'US'::character varying])::text[])))
);

ALTER TABLE ONLY public.organizations FORCE ROW LEVEL SECURITY;


--
-- Name: product_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_members (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    product_id integer NOT NULL,
    role character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id integer NOT NULL,
    tenant_id uuid NOT NULL
);

ALTER TABLE ONLY public.product_members FORCE ROW LEVEL SECURITY;


--
-- Name: product_members_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.product_members_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: product_members_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.product_members_id_seq OWNED BY public.product_members.id;


--
-- Name: product_properties; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_properties (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying NOT NULL,
    "position" integer DEFAULT 0,
    product_id integer NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    value character varying,
    tenant_id uuid NOT NULL
);

ALTER TABLE ONLY public.product_properties FORCE ROW LEVEL SECURITY;


--
-- Name: product_properties_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.product_properties_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: product_properties_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.product_properties_id_seq OWNED BY public.product_properties.id;


--
-- Name: products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products (
    id bigint NOT NULL,
    channel character varying,
    code character varying,
    country character varying,
    created_at timestamp(6) without time zone NOT NULL,
    deadline date,
    kind character varying DEFAULT 'item'::character varying NOT NULL,
    name character varying NOT NULL,
    notion_url character varying,
    owner_id integer,
    parent_id integer,
    "position" integer DEFAULT 0,
    product_type character varying DEFAULT '기획'::character varying,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id uuid NOT NULL,
    workspace_id bigint
);

ALTER TABLE ONLY public.products FORCE ROW LEVEL SECURITY;


--
-- Name: products_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.products_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.products_id_seq OWNED BY public.products.id;


--
-- Name: role_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_assignments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    account_id uuid NOT NULL,
    role_key character varying NOT NULL,
    scope_type character varying DEFAULT 'tenant'::character varying NOT NULL,
    market character varying,
    granted_by uuid,
    granted_at timestamp(6) without time zone DEFAULT now() NOT NULL,
    expires_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    scope_product_id bigint,
    scope_component_id bigint,
    scope_workspace_id bigint,
    CONSTRAINT ra_owner_tenant_wide CHECK ((((role_key)::text <> 'owner'::text) OR ((scope_workspace_id IS NULL) AND (scope_product_id IS NULL) AND (scope_component_id IS NULL)))),
    CONSTRAINT ra_scope_coherence CHECK (((((scope_type)::text = 'tenant'::text) AND (scope_workspace_id IS NULL) AND (scope_product_id IS NULL) AND (scope_component_id IS NULL)) OR (((scope_type)::text = 'workspace'::text) AND (scope_workspace_id IS NOT NULL) AND (scope_product_id IS NULL) AND (scope_component_id IS NULL)) OR (((scope_type)::text = 'product'::text) AND (scope_workspace_id IS NULL) AND (scope_product_id IS NOT NULL) AND (scope_component_id IS NULL)) OR (((scope_type)::text = 'component'::text) AND (scope_workspace_id IS NULL) AND (scope_product_id IS NULL) AND (scope_component_id IS NOT NULL)))),
    CONSTRAINT role_assignments_role_key_check CHECK (((role_key)::text = ANY ((ARRAY['owner'::character varying, 'brand_admin'::character varying, 'ra_reviewer'::character varying, 'approver'::character varying, 'assignee'::character varying, 'contributor'::character varying, 'viewer'::character varying, 'external_collaborator'::character varying])::text[]))),
    CONSTRAINT role_assignments_scope_type_check CHECK (((scope_type)::text = ANY (ARRAY['tenant'::text, 'workspace'::text, 'product'::text, 'component'::text])))
);

ALTER TABLE ONLY public.role_assignments FORCE ROW LEVEL SECURITY;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: screening_findings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.screening_findings (
    id bigint NOT NULL,
    box_h double precision,
    box_w double precision,
    box_x double precision,
    box_y double precision,
    citation character varying,
    confidence integer DEFAULT 80,
    created_at timestamp(6) without time zone NOT NULL,
    decision character varying,
    element_type character varying,
    human_review_required boolean DEFAULT false,
    issue_description text,
    "position" integer DEFAULT 0,
    recommended_action text,
    screening_run_id integer NOT NULL,
    severity character varying,
    subject character varying,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id uuid NOT NULL
);

ALTER TABLE ONLY public.screening_findings FORCE ROW LEVEL SECURITY;


--
-- Name: screening_findings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.screening_findings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: screening_findings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.screening_findings_id_seq OWNED BY public.screening_findings.id;


--
-- Name: screening_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.screening_runs (
    id bigint NOT NULL,
    component_version_id integer NOT NULL,
    country character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    decision character varying,
    requested_by_id integer,
    status character varying DEFAULT 'completed'::character varying,
    summary text,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id uuid NOT NULL
);

ALTER TABLE ONLY public.screening_runs FORCE ROW LEVEL SECURITY;


--
-- Name: screening_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.screening_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: screening_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.screening_runs_id_seq OWNED BY public.screening_runs.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    avatar_color character varying DEFAULT '#8e0300'::character varying,
    created_at timestamp(6) without time zone NOT NULL,
    email character varying,
    name character varying NOT NULL,
    role character varying DEFAULT 'pm'::character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: workspaces; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workspaces (
    id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    name character varying NOT NULL,
    "position" integer DEFAULT 0,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.workspaces FORCE ROW LEVEL SECURITY;


--
-- Name: workspaces_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.workspaces_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: workspaces_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.workspaces_id_seq OWNED BY public.workspaces.id;


--
-- Name: active_storage_attachments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments ALTER COLUMN id SET DEFAULT nextval('public.active_storage_attachments_id_seq'::regclass);


--
-- Name: active_storage_blobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs ALTER COLUMN id SET DEFAULT nextval('public.active_storage_blobs_id_seq'::regclass);


--
-- Name: active_storage_variant_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records ALTER COLUMN id SET DEFAULT nextval('public.active_storage_variant_records_id_seq'::regclass);


--
-- Name: ad_risk_expressions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ad_risk_expressions ALTER COLUMN id SET DEFAULT nextval('public.ad_risk_expressions_id_seq'::regclass);


--
-- Name: annotation_comments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.annotation_comments ALTER COLUMN id SET DEFAULT nextval('public.annotation_comments_id_seq'::regclass);


--
-- Name: annotations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.annotations ALTER COLUMN id SET DEFAULT nextval('public.annotations_id_seq'::regclass);


--
-- Name: approval_request_reviewers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_request_reviewers ALTER COLUMN id SET DEFAULT nextval('public.approval_request_reviewers_id_seq'::regclass);


--
-- Name: approval_requests id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_requests ALTER COLUMN id SET DEFAULT nextval('public.approval_requests_id_seq'::regclass);


--
-- Name: approval_steps id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_steps ALTER COLUMN id SET DEFAULT nextval('public.approval_steps_id_seq'::regclass);


--
-- Name: audit_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs ALTER COLUMN id SET DEFAULT nextval('public.audit_logs_id_seq'::regclass);


--
-- Name: component_versions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.component_versions ALTER COLUMN id SET DEFAULT nextval('public.component_versions_id_seq'::regclass);


--
-- Name: components id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.components ALTER COLUMN id SET DEFAULT nextval('public.components_id_seq'::regclass);


--
-- Name: ingredient_limits id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingredient_limits ALTER COLUMN id SET DEFAULT nextval('public.ingredient_limits_id_seq'::regclass);


--
-- Name: ingredients id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingredients ALTER COLUMN id SET DEFAULT nextval('public.ingredients_id_seq'::regclass);


--
-- Name: label_requirements id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.label_requirements ALTER COLUMN id SET DEFAULT nextval('public.label_requirements_id_seq'::regclass);


--
-- Name: label_texts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.label_texts ALTER COLUMN id SET DEFAULT nextval('public.label_texts_id_seq'::regclass);


--
-- Name: product_members id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_members ALTER COLUMN id SET DEFAULT nextval('public.product_members_id_seq'::regclass);


--
-- Name: product_properties id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_properties ALTER COLUMN id SET DEFAULT nextval('public.product_properties_id_seq'::regclass);


--
-- Name: products id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products ALTER COLUMN id SET DEFAULT nextval('public.products_id_seq'::regclass);


--
-- Name: screening_findings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.screening_findings ALTER COLUMN id SET DEFAULT nextval('public.screening_findings_id_seq'::regclass);


--
-- Name: screening_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.screening_runs ALTER COLUMN id SET DEFAULT nextval('public.screening_runs_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: workspaces id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspaces ALTER COLUMN id SET DEFAULT nextval('public.workspaces_id_seq'::regclass);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: ad_risk_expressions ad_risk_expressions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ad_risk_expressions
    ADD CONSTRAINT ad_risk_expressions_pkey PRIMARY KEY (id);


--
-- Name: annotation_comments annotation_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.annotation_comments
    ADD CONSTRAINT annotation_comments_pkey PRIMARY KEY (id);


--
-- Name: annotation_comments annotation_comments_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.annotation_comments
    ADD CONSTRAINT annotation_comments_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: annotations annotations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.annotations
    ADD CONSTRAINT annotations_pkey PRIMARY KEY (id);


--
-- Name: annotations annotations_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.annotations
    ADD CONSTRAINT annotations_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: approval_request_reviewers approval_request_reviewers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_request_reviewers
    ADD CONSTRAINT approval_request_reviewers_pkey PRIMARY KEY (id);


--
-- Name: approval_requests approval_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_requests
    ADD CONSTRAINT approval_requests_pkey PRIMARY KEY (id);


--
-- Name: approval_requests approval_requests_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_requests
    ADD CONSTRAINT approval_requests_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: approval_steps approval_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_steps
    ADD CONSTRAINT approval_steps_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: component_versions component_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.component_versions
    ADD CONSTRAINT component_versions_pkey PRIMARY KEY (id);


--
-- Name: component_versions component_versions_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.component_versions
    ADD CONSTRAINT component_versions_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: components components_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.components
    ADD CONSTRAINT components_pkey PRIMARY KEY (id);


--
-- Name: components components_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.components
    ADD CONSTRAINT components_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: ingredient_limits ingredient_limits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingredient_limits
    ADD CONSTRAINT ingredient_limits_pkey PRIMARY KEY (id);


--
-- Name: ingredients ingredients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingredients
    ADD CONSTRAINT ingredients_pkey PRIMARY KEY (id);


--
-- Name: invitations invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_pkey PRIMARY KEY (id);


--
-- Name: label_requirements label_requirements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.label_requirements
    ADD CONSTRAINT label_requirements_pkey PRIMARY KEY (id);


--
-- Name: label_texts label_texts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.label_texts
    ADD CONSTRAINT label_texts_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: product_members product_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_members
    ADD CONSTRAINT product_members_pkey PRIMARY KEY (id);


--
-- Name: product_properties product_properties_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_properties
    ADD CONSTRAINT product_properties_pkey PRIMARY KEY (id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: products products_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: role_assignments role_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_assignments
    ADD CONSTRAINT role_assignments_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: screening_findings screening_findings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.screening_findings
    ADD CONSTRAINT screening_findings_pkey PRIMARY KEY (id);


--
-- Name: screening_runs screening_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.screening_runs
    ADD CONSTRAINT screening_runs_pkey PRIMARY KEY (id);


--
-- Name: screening_runs screening_runs_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.screening_runs
    ADD CONSTRAINT screening_runs_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: workspaces workspaces_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT workspaces_pkey PRIMARY KEY (id);


--
-- Name: workspaces workspaces_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT workspaces_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: accounts_tenant_provider_subject_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX accounts_tenant_provider_subject_key ON public.accounts USING btree (tenant_id, idp_provider, idp_subject) WHERE (idp_subject IS NOT NULL);


--
-- Name: arr_tenant_request_reviewer_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX arr_tenant_request_reviewer_key ON public.approval_request_reviewers USING btree (tenant_id, approval_request_id, reviewer_id);


--
-- Name: arr_tenant_reviewer_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX arr_tenant_reviewer_idx ON public.approval_request_reviewers USING btree (tenant_id, reviewer_id);


--
-- Name: idx_on_tenant_id_resource_type_resource_id_ts_0d52db2ecc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_tenant_id_resource_type_resource_id_ts_0d52db2ecc ON public.audit_logs USING btree (tenant_id, resource_type, resource_id, ts);


--
-- Name: idx_ra_eligible_approver_v3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ra_eligible_approver_v3 ON public.role_assignments USING btree (tenant_id, role_key) WHERE ((scope_workspace_id IS NULL) AND (scope_product_id IS NULL) AND (scope_component_id IS NULL));


--
-- Name: idx_unique_product_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_unique_product_code ON public.products USING btree (code) WHERE ((code IS NOT NULL) AND ((code)::text <> ''::text));


--
-- Name: index_accounts_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounts_on_tenant_id ON public.accounts USING btree (tenant_id);


--
-- Name: index_accounts_on_tenant_id_and_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounts_on_tenant_id_and_email ON public.accounts USING btree (tenant_id, email);


--
-- Name: index_accounts_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounts_on_user_id ON public.accounts USING btree (user_id);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_ad_risk_expressions_on_country; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ad_risk_expressions_on_country ON public.ad_risk_expressions USING btree (country);


--
-- Name: index_annotation_comments_on_annotation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_annotation_comments_on_annotation_id ON public.annotation_comments USING btree (annotation_id);


--
-- Name: index_annotation_comments_on_author_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_annotation_comments_on_author_id ON public.annotation_comments USING btree (author_id);


--
-- Name: index_annotation_comments_on_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_annotation_comments_on_parent_id ON public.annotation_comments USING btree (parent_id);


--
-- Name: index_annotation_comments_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_annotation_comments_on_tenant_id ON public.annotation_comments USING btree (tenant_id);


--
-- Name: index_annotations_on_component_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_annotations_on_component_version_id ON public.annotations USING btree (component_version_id);


--
-- Name: index_annotations_on_component_version_id_and_seq; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_annotations_on_component_version_id_and_seq ON public.annotations USING btree (component_version_id, seq);


--
-- Name: index_annotations_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_annotations_on_created_by_id ON public.annotations USING btree (created_by_id);


--
-- Name: index_annotations_on_resolved_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_annotations_on_resolved_by_id ON public.annotations USING btree (resolved_by_id);


--
-- Name: index_annotations_on_resolved_in_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_annotations_on_resolved_in_version_id ON public.annotations USING btree (resolved_in_version_id);


--
-- Name: index_annotations_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_annotations_on_tenant_id ON public.annotations USING btree (tenant_id);


--
-- Name: index_approval_requests_on_tenant_id_and_component_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_approval_requests_on_tenant_id_and_component_version_id ON public.approval_requests USING btree (tenant_id, component_version_id);


--
-- Name: index_approval_requests_on_tenant_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_approval_requests_on_tenant_id_and_status ON public.approval_requests USING btree (tenant_id, status);


--
-- Name: index_approval_steps_on_tenant_id_and_approval_request_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_approval_steps_on_tenant_id_and_approval_request_id ON public.approval_steps USING btree (tenant_id, approval_request_id);


--
-- Name: index_audit_logs_on_tenant_id_and_actor_id_and_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_tenant_id_and_actor_id_and_ts ON public.audit_logs USING btree (tenant_id, actor_id, ts);


--
-- Name: index_audit_logs_on_tenant_id_and_outcome; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_tenant_id_and_outcome ON public.audit_logs USING btree (tenant_id, outcome);


--
-- Name: index_audit_logs_on_tenant_id_and_tenant_seq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_audit_logs_on_tenant_id_and_tenant_seq ON public.audit_logs USING btree (tenant_id, tenant_seq);


--
-- Name: index_audit_logs_on_tenant_id_and_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_tenant_id_and_ts ON public.audit_logs USING btree (tenant_id, ts);


--
-- Name: index_component_versions_on_component_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_component_versions_on_component_id ON public.component_versions USING btree (component_id);


--
-- Name: index_component_versions_on_component_id_and_version_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_component_versions_on_component_id_and_version_number ON public.component_versions USING btree (component_id, version_number);


--
-- Name: index_component_versions_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_component_versions_on_created_by_id ON public.component_versions USING btree (created_by_id);


--
-- Name: index_component_versions_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_component_versions_on_tenant_id ON public.component_versions USING btree (tenant_id);


--
-- Name: index_components_on_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_components_on_product_id ON public.components USING btree (product_id);


--
-- Name: index_components_on_product_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_components_on_product_id_and_position ON public.components USING btree (product_id, "position");


--
-- Name: index_components_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_components_on_tenant_id ON public.components USING btree (tenant_id);


--
-- Name: index_ingredient_limits_on_country_and_inci_canonical; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ingredient_limits_on_country_and_inci_canonical ON public.ingredient_limits USING btree (country, inci_canonical);


--
-- Name: index_ingredients_on_component_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ingredients_on_component_version_id ON public.ingredients USING btree (component_version_id);


--
-- Name: index_ingredients_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ingredients_on_tenant_id ON public.ingredients USING btree (tenant_id);


--
-- Name: index_invitations_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invitations_on_token_digest ON public.invitations USING btree (token_digest);


--
-- Name: index_label_requirements_on_country; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_label_requirements_on_country ON public.label_requirements USING btree (country);


--
-- Name: index_label_texts_on_component_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_label_texts_on_component_version_id ON public.label_texts USING btree (component_version_id);


--
-- Name: index_label_texts_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_label_texts_on_tenant_id ON public.label_texts USING btree (tenant_id);


--
-- Name: index_product_members_on_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_product_members_on_product_id ON public.product_members USING btree (product_id);


--
-- Name: index_product_members_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_product_members_on_tenant_id ON public.product_members USING btree (tenant_id);


--
-- Name: index_product_members_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_product_members_on_user_id ON public.product_members USING btree (user_id);


--
-- Name: index_product_properties_on_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_product_properties_on_product_id ON public.product_properties USING btree (product_id);


--
-- Name: index_product_properties_on_product_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_product_properties_on_product_id_and_position ON public.product_properties USING btree (product_id, "position");


--
-- Name: index_product_properties_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_product_properties_on_tenant_id ON public.product_properties USING btree (tenant_id);


--
-- Name: index_products_on_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_products_on_owner_id ON public.products USING btree (owner_id);


--
-- Name: index_products_on_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_products_on_parent_id ON public.products USING btree (parent_id);


--
-- Name: index_products_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_products_on_tenant_id ON public.products USING btree (tenant_id);


--
-- Name: index_products_on_workspace_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_products_on_workspace_id ON public.products USING btree (workspace_id);


--
-- Name: index_role_assignments_on_tenant_id_and_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_role_assignments_on_tenant_id_and_account_id ON public.role_assignments USING btree (tenant_id, account_id);


--
-- Name: index_screening_findings_on_screening_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_screening_findings_on_screening_run_id ON public.screening_findings USING btree (screening_run_id);


--
-- Name: index_screening_findings_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_screening_findings_on_tenant_id ON public.screening_findings USING btree (tenant_id);


--
-- Name: index_screening_runs_on_component_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_screening_runs_on_component_version_id ON public.screening_runs USING btree (component_version_id);


--
-- Name: index_screening_runs_on_requested_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_screening_runs_on_requested_by_id ON public.screening_runs USING btree (requested_by_id);


--
-- Name: index_screening_runs_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_screening_runs_on_tenant_id ON public.screening_runs USING btree (tenant_id);


--
-- Name: index_workspaces_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workspaces_on_tenant_id ON public.workspaces USING btree (tenant_id);


--
-- Name: invitations_tenant_list_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX invitations_tenant_list_idx ON public.invitations USING btree (tenant_id, created_at);


--
-- Name: invitations_tenant_open_email_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX invitations_tenant_open_email_key ON public.invitations USING btree (tenant_id, email) WHERE ((accepted_at IS NULL) AND (revoked_at IS NULL));


--
-- Name: uniq_role_assignment_v3; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uniq_role_assignment_v3 ON public.role_assignments USING btree (tenant_id, account_id, role_key, scope_workspace_id, scope_product_id, scope_component_id, market) NULLS NOT DISTINCT;


--
-- Name: audit_logs audit_logs_no_mutate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_logs_no_mutate BEFORE DELETE OR UPDATE ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION public.audit_logs_immutable();


--
-- Name: annotation_comments annotation_comments_annotation_tenant_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.annotation_comments
    ADD CONSTRAINT annotation_comments_annotation_tenant_fkey FOREIGN KEY (tenant_id, annotation_id) REFERENCES public.annotations(tenant_id, id);


--
-- Name: annotation_comments annotation_comments_parent_tenant_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.annotation_comments
    ADD CONSTRAINT annotation_comments_parent_tenant_fkey FOREIGN KEY (tenant_id, parent_id) REFERENCES public.annotation_comments(tenant_id, id);


--
-- Name: annotations annotations_cv_tenant_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.annotations
    ADD CONSTRAINT annotations_cv_tenant_fkey FOREIGN KEY (tenant_id, component_version_id) REFERENCES public.component_versions(tenant_id, id);


--
-- Name: annotations annotations_resolved_cv_tenant_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.annotations
    ADD CONSTRAINT annotations_resolved_cv_tenant_fkey FOREIGN KEY (tenant_id, resolved_in_version_id) REFERENCES public.component_versions(tenant_id, id);


--
-- Name: approval_requests approval_requests_cv_tenant_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_requests
    ADD CONSTRAINT approval_requests_cv_tenant_fkey FOREIGN KEY (tenant_id, component_version_id) REFERENCES public.component_versions(tenant_id, id);


--
-- Name: approval_steps approval_steps_request_tenant_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_steps
    ADD CONSTRAINT approval_steps_request_tenant_fkey FOREIGN KEY (tenant_id, approval_request_id) REFERENCES public.approval_requests(tenant_id, id);


--
-- Name: approval_request_reviewers arr_request_tenant_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_request_reviewers
    ADD CONSTRAINT arr_request_tenant_fkey FOREIGN KEY (tenant_id, approval_request_id) REFERENCES public.approval_requests(tenant_id, id);


--
-- Name: component_versions component_versions_component_tenant_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.component_versions
    ADD CONSTRAINT component_versions_component_tenant_fkey FOREIGN KEY (tenant_id, component_id) REFERENCES public.components(tenant_id, id);


--
-- Name: components components_product_tenant_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.components
    ADD CONSTRAINT components_product_tenant_fkey FOREIGN KEY (tenant_id, product_id) REFERENCES public.products(tenant_id, id);


--
-- Name: products fk_products_workspace; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT fk_products_workspace FOREIGN KEY (tenant_id, workspace_id) REFERENCES public.workspaces(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: annotation_comments fk_rails_246a8da3db; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.annotation_comments
    ADD CONSTRAINT fk_rails_246a8da3db FOREIGN KEY (author_id) REFERENCES public.users(id);


--
-- Name: product_members fk_rails_274f9b79fe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_members
    ADD CONSTRAINT fk_rails_274f9b79fe FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: role_assignments fk_rails_285fb9b6dc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_assignments
    ADD CONSTRAINT fk_rails_285fb9b6dc FOREIGN KEY (scope_product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: approval_request_reviewers fk_rails_3031802847; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_request_reviewers
    ADD CONSTRAINT fk_rails_3031802847 FOREIGN KEY (reviewer_id) REFERENCES public.users(id);


--
-- Name: approval_requests fk_rails_41314c9a90; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_requests
    ADD CONSTRAINT fk_rails_41314c9a90 FOREIGN KEY (submitter_id) REFERENCES public.users(id);


--
-- Name: annotations fk_rails_42d457ff79; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.annotations
    ADD CONSTRAINT fk_rails_42d457ff79 FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: role_assignments fk_rails_62bfe9a4bf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_assignments
    ADD CONSTRAINT fk_rails_62bfe9a4bf FOREIGN KEY (tenant_id) REFERENCES public.organizations(id);


--
-- Name: products fk_rails_7536ff0cd9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT fk_rails_7536ff0cd9 FOREIGN KEY (owner_id) REFERENCES public.users(id);


--
-- Name: annotations fk_rails_854dc436e2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.annotations
    ADD CONSTRAINT fk_rails_854dc436e2 FOREIGN KEY (resolved_by_id) REFERENCES public.users(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: invitations fk_rails_a35f83f43c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_rails_a35f83f43c FOREIGN KEY (scope_product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: invitations fk_rails_a3fa16e2ba; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_rails_a3fa16e2ba FOREIGN KEY (scope_workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: accounts fk_rails_b1e30bebc8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT fk_rails_b1e30bebc8 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: role_assignments fk_rails_cfc01d9f91; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_assignments
    ADD CONSTRAINT fk_rails_cfc01d9f91 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: screening_runs fk_rails_d6c9acfb4f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.screening_runs
    ADD CONSTRAINT fk_rails_d6c9acfb4f FOREIGN KEY (requested_by_id) REFERENCES public.users(id);


--
-- Name: component_versions fk_rails_e10560f404; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.component_versions
    ADD CONSTRAINT fk_rails_e10560f404 FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: role_assignments fk_rails_e315702a7c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_assignments
    ADD CONSTRAINT fk_rails_e315702a7c FOREIGN KEY (scope_workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: approval_steps fk_rails_e41a89c75c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_steps
    ADD CONSTRAINT fk_rails_e41a89c75c FOREIGN KEY (approver_id) REFERENCES public.users(id);


--
-- Name: role_assignments fk_rails_e724ce2fcb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_assignments
    ADD CONSTRAINT fk_rails_e724ce2fcb FOREIGN KEY (scope_component_id) REFERENCES public.components(id) ON DELETE CASCADE;


--
-- Name: accounts fk_rails_ec5cb9c3f9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT fk_rails_ec5cb9c3f9 FOREIGN KEY (tenant_id) REFERENCES public.organizations(id);


--
-- Name: invitations fk_rails_f10119a075; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_rails_f10119a075 FOREIGN KEY (scope_component_id) REFERENCES public.components(id) ON DELETE CASCADE;


--
-- Name: invitations fk_rails_f2ab2431e2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_rails_f2ab2431e2 FOREIGN KEY (tenant_id) REFERENCES public.organizations(id);


--
-- Name: ingredients ingredients_cv_tenant_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingredients
    ADD CONSTRAINT ingredients_cv_tenant_fkey FOREIGN KEY (tenant_id, component_version_id) REFERENCES public.component_versions(tenant_id, id);


--
-- Name: label_texts label_texts_cv_tenant_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.label_texts
    ADD CONSTRAINT label_texts_cv_tenant_fkey FOREIGN KEY (tenant_id, component_version_id) REFERENCES public.component_versions(tenant_id, id);


--
-- Name: product_members product_members_product_tenant_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_members
    ADD CONSTRAINT product_members_product_tenant_fkey FOREIGN KEY (tenant_id, product_id) REFERENCES public.products(tenant_id, id);


--
-- Name: product_properties product_properties_product_tenant_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_properties
    ADD CONSTRAINT product_properties_product_tenant_fkey FOREIGN KEY (tenant_id, product_id) REFERENCES public.products(tenant_id, id);


--
-- Name: products products_parent_tenant_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_parent_tenant_fkey FOREIGN KEY (tenant_id, parent_id) REFERENCES public.products(tenant_id, id);


--
-- Name: screening_findings screening_findings_run_tenant_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.screening_findings
    ADD CONSTRAINT screening_findings_run_tenant_fkey FOREIGN KEY (tenant_id, screening_run_id) REFERENCES public.screening_runs(tenant_id, id);


--
-- Name: screening_runs screening_runs_cv_tenant_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.screening_runs
    ADD CONSTRAINT screening_runs_cv_tenant_fkey FOREIGN KEY (tenant_id, component_version_id) REFERENCES public.component_versions(tenant_id, id);


--
-- Name: accounts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: annotation_comments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.annotation_comments ENABLE ROW LEVEL SECURITY;

--
-- Name: annotations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.annotations ENABLE ROW LEVEL SECURITY;

--
-- Name: approval_request_reviewers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.approval_request_reviewers ENABLE ROW LEVEL SECURITY;

--
-- Name: approval_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.approval_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: approval_steps; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.approval_steps ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: component_versions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.component_versions ENABLE ROW LEVEL SECURITY;

--
-- Name: components; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.components ENABLE ROW LEVEL SECURITY;

--
-- Name: ingredients; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ingredients ENABLE ROW LEVEL SECURITY;

--
-- Name: invitations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;

--
-- Name: label_texts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.label_texts ENABLE ROW LEVEL SECURITY;

--
-- Name: organizations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

--
-- Name: product_members; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.product_members ENABLE ROW LEVEL SECURITY;

--
-- Name: product_properties; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.product_properties ENABLE ROW LEVEL SECURITY;

--
-- Name: products; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

--
-- Name: role_assignments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.role_assignments ENABLE ROW LEVEL SECURITY;

--
-- Name: screening_findings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.screening_findings ENABLE ROW LEVEL SECURITY;

--
-- Name: screening_runs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.screening_runs ENABLE ROW LEVEL SECURITY;

--
-- Name: accounts tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.accounts USING ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- Name: annotation_comments tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.annotation_comments USING ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- Name: annotations tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.annotations USING ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- Name: approval_request_reviewers tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.approval_request_reviewers USING ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- Name: approval_requests tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.approval_requests USING ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- Name: approval_steps tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.approval_steps USING ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- Name: audit_logs tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.audit_logs USING ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- Name: component_versions tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.component_versions USING ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- Name: components tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.components USING ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- Name: ingredients tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.ingredients USING ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- Name: invitations tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.invitations USING ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- Name: label_texts tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.label_texts USING ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- Name: organizations tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.organizations USING ((id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- Name: product_members tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.product_members USING ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- Name: product_properties tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.product_properties USING ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- Name: products tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.products USING ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- Name: role_assignments tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.role_assignments USING ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- Name: screening_findings tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.screening_findings USING ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- Name: screening_runs tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.screening_runs USING ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- Name: workspaces tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.workspaces USING ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- Name: workspaces; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260707000001'),
('20260706000001'),
('20260705000007'),
('20260705000006'),
('20260705000005'),
('20260705000004'),
('20260705000003'),
('20260705000002'),
('20260705000001'),
('20260704000005'),
('20260704000004'),
('20260704000003'),
('20260704000002'),
('20260704000001'),
('20260702000002'),
('20260702000001'),
('20260701000004'),
('20260701000003'),
('20260701000002'),
('20260701000001'),
('20260630000003'),
('20260630000002'),
('20260630000001'),
('20260629000003'),
('20260629000002'),
('20260629000001'),
('20260628000012'),
('20260628000011'),
('20260628000010'),
('20260628000009'),
('20260628000008'),
('20260628000007'),
('20260628000006'),
('20260628000005'),
('20260628000004'),
('20260628000003'),
('20260628000002'),
('20260628000001'),
('20260625120000'),
('20260624220000'),
('20260624112556'),
('20260624054313'),
('20260624035542'),
('20260623140000');

