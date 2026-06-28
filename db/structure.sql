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
    updated_at timestamp(6) without time zone NOT NULL
);


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
    updated_at timestamp(6) without time zone NOT NULL
);


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
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


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
    version_number integer NOT NULL
);


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
    updated_at timestamp(6) without time zone NOT NULL
);


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
    updated_at timestamp(6) without time zone NOT NULL
);


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
    updated_at timestamp(6) without time zone NOT NULL
);


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
    user_id integer NOT NULL
);


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
    value character varying
);


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
    updated_at timestamp(6) without time zone NOT NULL
);


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
    scope_id uuid,
    market character varying,
    granted_by uuid,
    granted_at timestamp(6) without time zone DEFAULT now() NOT NULL,
    expires_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT role_assignments_role_key_check CHECK (((role_key)::text = ANY ((ARRAY['owner'::character varying, 'brand_admin'::character varying, 'ra_reviewer'::character varying, 'approver'::character varying, 'assignee'::character varying, 'contributor'::character varying, 'viewer'::character varying, 'external_collaborator'::character varying])::text[]))),
    CONSTRAINT role_assignments_scope_type_check CHECK (((scope_type)::text = ANY ((ARRAY['tenant'::character varying, 'product'::character varying, 'component'::character varying])::text[])))
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
    updated_at timestamp(6) without time zone NOT NULL
);


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
    approved_at timestamp(6) without time zone,
    approved_by_id integer,
    component_version_id integer NOT NULL,
    country character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    decision character varying,
    requested_by_id integer,
    status character varying DEFAULT 'completed'::character varying,
    summary text,
    updated_at timestamp(6) without time zone NOT NULL
);


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
-- Name: annotations annotations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.annotations
    ADD CONSTRAINT annotations_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: component_versions component_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.component_versions
    ADD CONSTRAINT component_versions_pkey PRIMARY KEY (id);


--
-- Name: components components_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.components
    ADD CONSTRAINT components_pkey PRIMARY KEY (id);


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
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


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
-- Name: index_components_on_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_components_on_product_id ON public.components USING btree (product_id);


--
-- Name: index_components_on_product_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_components_on_product_id_and_position ON public.components USING btree (product_id, "position");


--
-- Name: index_ingredient_limits_on_country_and_inci_canonical; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ingredient_limits_on_country_and_inci_canonical ON public.ingredient_limits USING btree (country, inci_canonical);


--
-- Name: index_ingredients_on_component_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ingredients_on_component_version_id ON public.ingredients USING btree (component_version_id);


--
-- Name: index_label_requirements_on_country; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_label_requirements_on_country ON public.label_requirements USING btree (country);


--
-- Name: index_label_texts_on_component_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_label_texts_on_component_version_id ON public.label_texts USING btree (component_version_id);


--
-- Name: index_product_members_on_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_product_members_on_product_id ON public.product_members USING btree (product_id);


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
-- Name: index_products_on_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_products_on_owner_id ON public.products USING btree (owner_id);


--
-- Name: index_products_on_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_products_on_parent_id ON public.products USING btree (parent_id);


--
-- Name: index_role_assignments_on_tenant_id_and_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_role_assignments_on_tenant_id_and_account_id ON public.role_assignments USING btree (tenant_id, account_id);


--
-- Name: index_screening_findings_on_screening_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_screening_findings_on_screening_run_id ON public.screening_findings USING btree (screening_run_id);


--
-- Name: index_screening_runs_on_approved_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_screening_runs_on_approved_by_id ON public.screening_runs USING btree (approved_by_id);


--
-- Name: index_screening_runs_on_component_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_screening_runs_on_component_version_id ON public.screening_runs USING btree (component_version_id);


--
-- Name: index_screening_runs_on_requested_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_screening_runs_on_requested_by_id ON public.screening_runs USING btree (requested_by_id);


--
-- Name: uniq_role_assignment; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uniq_role_assignment ON public.role_assignments USING btree (tenant_id, account_id, role_key, scope_id, market) NULLS NOT DISTINCT;


--
-- Name: annotation_comments fk_rails_246a8da3db; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.annotation_comments
    ADD CONSTRAINT fk_rails_246a8da3db FOREIGN KEY (author_id) REFERENCES public.users(id);


--
-- Name: label_texts fk_rails_2605f7cdb1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.label_texts
    ADD CONSTRAINT fk_rails_2605f7cdb1 FOREIGN KEY (component_version_id) REFERENCES public.component_versions(id);


--
-- Name: product_members fk_rails_274f9b79fe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_members
    ADD CONSTRAINT fk_rails_274f9b79fe FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: annotations fk_rails_42d457ff79; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.annotations
    ADD CONSTRAINT fk_rails_42d457ff79 FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: annotations fk_rails_489cf3ecb1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.annotations
    ADD CONSTRAINT fk_rails_489cf3ecb1 FOREIGN KEY (component_version_id) REFERENCES public.component_versions(id);


--
-- Name: component_versions fk_rails_49cb5aeac1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.component_versions
    ADD CONSTRAINT fk_rails_49cb5aeac1 FOREIGN KEY (component_id) REFERENCES public.components(id);


--
-- Name: annotation_comments fk_rails_608f9bfb3b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.annotation_comments
    ADD CONSTRAINT fk_rails_608f9bfb3b FOREIGN KEY (annotation_id) REFERENCES public.annotations(id);


--
-- Name: role_assignments fk_rails_62bfe9a4bf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_assignments
    ADD CONSTRAINT fk_rails_62bfe9a4bf FOREIGN KEY (tenant_id) REFERENCES public.organizations(id);


--
-- Name: product_members fk_rails_6dda92f725; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_members
    ADD CONSTRAINT fk_rails_6dda92f725 FOREIGN KEY (product_id) REFERENCES public.products(id);


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
-- Name: products fk_rails_89506052d0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT fk_rails_89506052d0 FOREIGN KEY (parent_id) REFERENCES public.products(id);


--
-- Name: annotations fk_rails_911cdd80ea; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.annotations
    ADD CONSTRAINT fk_rails_911cdd80ea FOREIGN KEY (resolved_in_version_id) REFERENCES public.component_versions(id);


--
-- Name: screening_findings fk_rails_94c9a6ad2d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.screening_findings
    ADD CONSTRAINT fk_rails_94c9a6ad2d FOREIGN KEY (screening_run_id) REFERENCES public.screening_runs(id);


--
-- Name: product_properties fk_rails_97d15debea; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_properties
    ADD CONSTRAINT fk_rails_97d15debea FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: annotation_comments fk_rails_c2d5d9ba85; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.annotation_comments
    ADD CONSTRAINT fk_rails_c2d5d9ba85 FOREIGN KEY (parent_id) REFERENCES public.annotation_comments(id);


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
-- Name: screening_runs fk_rails_eb7d3b7fc1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.screening_runs
    ADD CONSTRAINT fk_rails_eb7d3b7fc1 FOREIGN KEY (component_version_id) REFERENCES public.component_versions(id);


--
-- Name: accounts fk_rails_ec5cb9c3f9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT fk_rails_ec5cb9c3f9 FOREIGN KEY (tenant_id) REFERENCES public.organizations(id);


--
-- Name: ingredients fk_rails_f0c59eb302; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingredients
    ADD CONSTRAINT fk_rails_f0c59eb302 FOREIGN KEY (component_version_id) REFERENCES public.component_versions(id);


--
-- Name: components fk_rails_f80e155e03; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.components
    ADD CONSTRAINT fk_rails_f80e155e03 FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: screening_runs fk_rails_fe66c052dc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.screening_runs
    ADD CONSTRAINT fk_rails_fe66c052dc FOREIGN KEY (approved_by_id) REFERENCES public.users(id);


--
-- Name: accounts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: organizations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

--
-- Name: role_assignments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.role_assignments ENABLE ROW LEVEL SECURITY;

--
-- Name: accounts tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.accounts USING ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- Name: organizations tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.organizations USING ((id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- Name: role_assignments tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.role_assignments USING ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.current_tenant_id'::text, true), ''::text))::uuid));


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
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

