--
-- PostgreSQL database dump
--

-- Dumped from database version 18.3
-- Dumped by pg_dump version 18.3

-- Started on 2026-06-22 08:17:12

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
-- TOC entry 2 (class 3079 OID 16389)
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- TOC entry 5214 (class 0 OID 0)
-- Dependencies: 2
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- TOC entry 243 (class 1255 OID 16667)
-- Name: trigger_set_timestamp(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trigger_set_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.trigger_set_timestamp() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 232 (class 1259 OID 16681)
-- Name: comment_likes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.comment_likes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    comment_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.comment_likes OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 16461)
-- Name: comments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.comments (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id uuid,
    post_id uuid,
    content character varying(500) NOT NULL,
    is_deleted boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    parent_id uuid
);


ALTER TABLE public.comments OWNER TO postgres;

--
-- TOC entry 224 (class 1259 OID 16484)
-- Name: follows; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.follows (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    follower_id uuid,
    following_id uuid,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.follows OWNER TO postgres;

--
-- TOC entry 228 (class 1259 OID 16576)
-- Name: group_members; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.group_members (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    group_id uuid,
    user_id uuid,
    role character varying(20) DEFAULT 'member'::character varying,
    joined_at timestamp without time zone DEFAULT now(),
    CONSTRAINT group_members_role_check CHECK (((role)::text = ANY ((ARRAY['admin'::character varying, 'member'::character varying])::text[])))
);


ALTER TABLE public.group_members OWNER TO postgres;

--
-- TOC entry 229 (class 1259 OID 16598)
-- Name: group_messages; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.group_messages (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    group_id uuid,
    sender_id uuid,
    content text,
    file_url character varying(255),
    file_size integer,
    is_edited boolean DEFAULT false,
    is_deleted boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    file_type character varying(20),
    file_name text,
    is_system boolean DEFAULT false,
    is_read boolean DEFAULT false
);


ALTER TABLE public.group_messages OWNER TO postgres;

--
-- TOC entry 227 (class 1259 OID 16557)
-- Name: groups; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.groups (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name character varying(100) NOT NULL,
    description text,
    type character varying(20) DEFAULT 'custom'::character varying,
    created_by uuid,
    is_private boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT now(),
    pinned_message_id uuid,
    CONSTRAINT groups_type_check CHECK (((type)::text = ANY ((ARRAY['promotion'::character varying, 'residence'::character varying, 'filiere'::character varying, 'custom'::character varying])::text[])))
);


ALTER TABLE public.groups OWNER TO postgres;

--
-- TOC entry 222 (class 1259 OID 16441)
-- Name: likes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.likes (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id uuid,
    post_id uuid,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.likes OWNER TO postgres;

--
-- TOC entry 226 (class 1259 OID 16532)
-- Name: messages; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.messages (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    sender_id uuid,
    receiver_id uuid,
    content text,
    is_edited boolean DEFAULT false,
    is_deleted boolean DEFAULT false,
    is_read boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    file_url character varying(255),
    file_type character varying(20),
    file_name character varying(255),
    file_size integer,
    CONSTRAINT messages_file_type_check CHECK (((file_type)::text = ANY ((ARRAY['image'::character varying, 'video'::character varying, 'document'::character varying, 'audio'::character varying])::text[])))
);


ALTER TABLE public.messages OWNER TO postgres;

--
-- TOC entry 230 (class 1259 OID 16621)
-- Name: notifications; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.notifications (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id uuid,
    type character varying(50) NOT NULL,
    content text NOT NULL,
    is_read boolean DEFAULT false,
    reference_id uuid,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.notifications OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 16422)
-- Name: posts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.posts (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id uuid,
    content text,
    media_url character varying(255),
    media_type character varying(20),
    media_size integer,
    tags text[],
    is_institutional boolean DEFAULT false,
    is_deleted boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    media_gallery jsonb DEFAULT '[]'::jsonb,
    CONSTRAINT posts_media_type_check CHECK (((media_type)::text = ANY ((ARRAY['photo'::character varying, 'video'::character varying, 'none'::character varying])::text[])))
);


ALTER TABLE public.posts OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 16504)
-- Name: reports; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.reports (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    reporter_id uuid,
    post_id uuid,
    comment_id uuid,
    reason text NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying,
    created_at timestamp without time zone DEFAULT now(),
    CONSTRAINT reports_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'reviewed'::character varying, 'resolved'::character varying])::text[])))
);


ALTER TABLE public.reports OWNER TO postgres;

--
-- TOC entry 231 (class 1259 OID 16639)
-- Name: sessions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sessions (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id uuid,
    token text NOT NULL,
    device_info text,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now(),
    expires_at timestamp without time zone NOT NULL
);


ALTER TABLE public.sessions OWNER TO postgres;

--
-- TOC entry 220 (class 1259 OID 16400)
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    username character varying(50) NOT NULL,
    email character varying(100) NOT NULL,
    password_hash character varying(255),
    full_name character varying(100) NOT NULL,
    bio text,
    avatar_url character varying(255),
    role character varying(20) DEFAULT 'student'::character varying,
    promotion character varying(50),
    residence character varying(100),
    filiere character varying(100),
    is_active boolean DEFAULT true,
    is_verified boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    CONSTRAINT users_role_check CHECK (((role)::text = ANY ((ARRAY['student'::character varying, 'moderator'::character varying, 'admin'::character varying, 'alumni'::character varying, 'concierge'::character varying])::text[])))
);


ALTER TABLE public.users OWNER TO postgres;

--
-- TOC entry 5208 (class 0 OID 16681)
-- Dependencies: 232
-- Data for Name: comment_likes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.comment_likes (id, comment_id, user_id, created_at) FROM stdin;
991e3d67-a59d-45cd-95f0-a348218ccd3d	575b042f-feef-40f8-a7df-de43b0036fbb	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	2026-05-06 09:03:43.997931
21615608-e553-4725-8a8b-787207680923	66da56bf-009f-4dfc-acf6-40f58c7cc067	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	2026-05-06 09:03:45.892548
cc1ed7b6-a139-4da8-8f53-9ac0173eb301	a85c636a-af7d-4d8e-ba4a-3c71218f62b3	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	2026-05-06 09:03:47.831179
7a1716b4-37af-45af-8edb-3d50239ea8db	0741d225-6c11-4366-9db7-3d6567cbfddd	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	2026-05-06 09:05:07.49544
eb67ffd6-b829-4ef7-b8ab-53e069af47b9	edbca193-a607-41b5-8e9c-332cf91dc999	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	2026-05-06 09:51:45.90874
6b550c6b-f06c-4cfd-95c0-ba01af5624d9	edbca193-a607-41b5-8e9c-332cf91dc999	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	2026-05-06 09:55:54.88131
f1042287-df3b-4392-a0a5-7535ec097bac	06b5b0e8-d99e-4ce8-93e7-a7fd7695ebd0	31100824-069e-4aa2-90fd-3a56ea6ad20a	2026-05-06 10:13:19.764819
c7762f03-554c-447b-a252-73ceea8ebe30	edbca193-a607-41b5-8e9c-332cf91dc999	31100824-069e-4aa2-90fd-3a56ea6ad20a	2026-05-06 10:13:21.167083
4bd74a99-b4ee-4bed-ac64-48e7b6845fe3	019cd6bf-35c4-4239-bc9e-f35de805ff54	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	2026-05-06 14:20:36.313783
\.


--
-- TOC entry 5199 (class 0 OID 16461)
-- Dependencies: 223
-- Data for Name: comments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.comments (id, user_id, post_id, content, is_deleted, created_at, updated_at, parent_id) FROM stdin;
f1c2198d-f43e-4f6c-9238-cd2b185633b4	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	94433f30-2260-4a88-80fe-33c41673d0d8	bjr	f	2026-05-06 08:57:11.772754	2026-05-06 08:57:11.772754	\N
4d482d20-f4e1-432d-b5a8-8614d0371801	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	94433f30-2260-4a88-80fe-33c41673d0d8	bjr	f	2026-05-06 08:57:12.639458	2026-05-06 08:57:12.639458	\N
0741d225-6c11-4366-9db7-3d6567cbfddd	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	94433f30-2260-4a88-80fe-33c41673d0d8	bjr	f	2026-05-06 08:57:13.234669	2026-05-06 08:57:13.234669	\N
df2e0c37-0291-4850-96f1-e0ec2b8e132e	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	94433f30-2260-4a88-80fe-33c41673d0d8	bjr	f	2026-05-06 08:57:13.683061	2026-05-06 08:57:13.683061	\N
ae688472-2da4-480d-8457-4995d73495a6	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	94433f30-2260-4a88-80fe-33c41673d0d8	bjr	f	2026-05-06 08:57:13.948539	2026-05-06 08:57:13.948539	\N
a85c636a-af7d-4d8e-ba4a-3c71218f62b3	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	94433f30-2260-4a88-80fe-33c41673d0d8	bjr	f	2026-05-06 08:57:14.142834	2026-05-06 08:57:14.142834	\N
66da56bf-009f-4dfc-acf6-40f58c7cc067	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	94433f30-2260-4a88-80fe-33c41673d0d8	bjr	f	2026-05-06 08:57:14.371478	2026-05-06 08:57:14.371478	\N
575b042f-feef-40f8-a7df-de43b0036fbb	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	94433f30-2260-4a88-80fe-33c41673d0d8	bjr	f	2026-05-06 08:57:14.60664	2026-05-06 08:57:14.60664	\N
64c34cc7-33f7-4a48-a38a-500f8aba4edf	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	94433f30-2260-4a88-80fe-33c41673d0d8	KDK	f	2026-05-06 09:05:10.497605	2026-05-06 09:05:10.497605	\N
edbca193-a607-41b5-8e9c-332cf91dc999	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	b2490b1e-c41f-4eed-8f99-7b11da9eb11c	super	f	2026-05-06 09:51:42.085849	2026-05-06 09:51:42.085849	\N
06b5b0e8-d99e-4ce8-93e7-a7fd7695ebd0	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	b2490b1e-c41f-4eed-8f99-7b11da9eb11c	carré	f	2026-05-06 09:56:00.897536	2026-05-06 09:56:00.897536	\N
019cd6bf-35c4-4239-bc9e-f35de805ff54	31100824-069e-4aa2-90fd-3a56ea6ad20a	b2490b1e-c41f-4eed-8f99-7b11da9eb11c	ok	f	2026-05-06 10:13:29.273579	2026-05-06 10:13:29.273579	\N
8f7eac81-6ef1-4f50-a0f8-b1ac8b08ff1e	dce21297-ed4d-44bf-955c-cfe7517c2959	e7dcf2ff-7d35-448f-adea-a3ea622bd9aa	kali	f	2026-06-19 22:30:58.359201	2026-06-19 22:30:58.359201	\N
\.


--
-- TOC entry 5200 (class 0 OID 16484)
-- Dependencies: 224
-- Data for Name: follows; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.follows (id, follower_id, following_id, created_at) FROM stdin;
d78426ec-bd24-4b0c-ad29-fd1d754ec090	31100824-069e-4aa2-90fd-3a56ea6ad20a	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	2026-04-28 14:10:20.863919
cd63fc85-94b5-45ce-92c6-6a2d9aba93d5	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	2026-05-06 09:49:55.930954
29a4e3b6-b74b-445d-a254-e23adb32a821	31100824-069e-4aa2-90fd-3a56ea6ad20a	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	2026-05-06 09:54:36.530194
794142f8-c3af-4c61-b400-dd9d0d28ca7e	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	31100824-069e-4aa2-90fd-3a56ea6ad20a	2026-05-06 09:55:34.008448
706b75b2-d623-40d2-8065-7b95dd1aa2cd	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	2026-05-06 09:55:45.375811
2593d6c4-0fb6-41db-8381-1411c660fd87	dce21297-ed4d-44bf-955c-cfe7517c2959	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	2026-06-19 22:29:20.420061
\.


--
-- TOC entry 5204 (class 0 OID 16576)
-- Dependencies: 228
-- Data for Name: group_members; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.group_members (id, group_id, user_id, role, joined_at) FROM stdin;
4f57a514-ab60-4225-aa13-cee4080093c4	c7886fb9-c0ac-4bd3-a8ec-0e834d07c7e1	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	member	2026-05-07 13:21:44.846861
d8669ae7-af76-408a-803d-e46fdd23da49	c177b8b9-29db-4c2e-99d9-866cf352313f	31100824-069e-4aa2-90fd-3a56ea6ad20a	admin	2026-05-07 13:30:28.726195
3154343e-4f6c-469d-bd10-330967ecd78d	c177b8b9-29db-4c2e-99d9-866cf352313f	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	member	2026-05-07 13:30:28.726195
a3aaabba-e0d2-40a5-a1e3-76d19c9bacf3	6bacd8af-10a1-4864-b1cd-7c80fd8a273a	31100824-069e-4aa2-90fd-3a56ea6ad20a	admin	2026-05-07 13:40:05.794818
1bb80d05-01e9-4a71-8999-45fae34d324d	6bacd8af-10a1-4864-b1cd-7c80fd8a273a	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	member	2026-05-07 13:40:05.794818
b770006f-1d1a-468f-b037-ab850c10d3ec	90cc54ac-55c2-4b94-96f1-ef9e9ab90cff	dce21297-ed4d-44bf-955c-cfe7517c2959	admin	2026-06-19 21:27:10.432149
d7b71d60-001e-457c-a0e7-fabca4902fe4	90cc54ac-55c2-4b94-96f1-ef9e9ab90cff	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	member	2026-06-19 21:27:10.432149
2d3beacb-0c70-4f14-82fa-1ff5cab67be3	90cc54ac-55c2-4b94-96f1-ef9e9ab90cff	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	member	2026-06-19 21:27:10.432149
956559c4-8239-47f7-91e7-30831042913a	46232cc4-6777-4a9d-bae1-00310cfef38a	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	admin	2026-05-06 09:58:57.528311
\.


--
-- TOC entry 5205 (class 0 OID 16598)
-- Dependencies: 229
-- Data for Name: group_messages; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.group_messages (id, group_id, sender_id, content, file_url, file_size, is_edited, is_deleted, created_at, updated_at, file_type, file_name, is_system, is_read) FROM stdin;
dcc14d8d-2c47-4a7f-a630-cfc3dc45e990	c7886fb9-c0ac-4bd3-a8ec-0e834d07c7e1	31100824-069e-4aa2-90fd-3a56ea6ad20a	Groupe "K" créé	\N	\N	f	f	2026-05-07 13:21:44.846861	2026-05-07 13:21:44.846861	\N	\N	t	f
7e0a446e-4d4d-4c20-ba3d-dfc99d9761f2	c7886fb9-c0ac-4bd3-a8ec-0e834d07c7e1	31100824-069e-4aa2-90fd-3a56ea6ad20a	wkamga a quitté le groupe	\N	\N	f	f	2026-05-07 13:30:17.666961	2026-05-07 13:30:17.666961	\N	\N	t	f
4086f06b-278d-4409-b345-d32f59043c51	c177b8b9-29db-4c2e-99d9-866cf352313f	31100824-069e-4aa2-90fd-3a56ea6ad20a	Groupe "R" créé	\N	\N	f	f	2026-05-07 13:30:28.726195	2026-05-07 13:30:28.726195	\N	\N	t	f
bf68a41d-54fc-4e97-905c-3280a5e71720	6bacd8af-10a1-4864-b1cd-7c80fd8a273a	31100824-069e-4aa2-90fd-3a56ea6ad20a	Groupe "E" créé	\N	\N	f	f	2026-05-07 13:40:05.794818	2026-05-07 13:40:05.794818	\N	\N	t	f
d1d0d4c5-c985-49d9-806e-bc6a2106f939	6bacd8af-10a1-4864-b1cd-7c80fd8a273a	31100824-069e-4aa2-90fd-3a56ea6ad20a	dj	\N	\N	f	f	2026-05-08 15:20:25.472931	2026-05-08 15:20:25.472931	\N	\N	f	f
4d98b7c6-1fb9-417a-94a4-6b68e991642d	6bacd8af-10a1-4864-b1cd-7c80fd8a273a	31100824-069e-4aa2-90fd-3a56ea6ad20a	📌 Message épinglé par wkamga	\N	\N	f	f	2026-05-08 15:20:28.468121	2026-05-08 15:20:28.468121	\N	\N	t	f
d53bc167-cfe0-4715-8575-1b8453796711	6bacd8af-10a1-4864-b1cd-7c80fd8a273a	31100824-069e-4aa2-90fd-3a56ea6ad20a	Message désépinglé par wkamga	\N	\N	f	f	2026-05-08 15:20:32.591282	2026-05-08 15:20:32.591282	\N	\N	t	f
2c94e597-8b3a-4801-b17d-84fbe97e37b3	46232cc4-6777-4a9d-bae1-00310cfef38a	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	Groupe "AA" créé	\N	\N	f	f	2026-05-06 09:58:57.528311	2026-05-06 09:58:57.528311	\N	\N	t	t
9881a151-ddfb-46f6-90d5-adcf6a827992	46232cc4-6777-4a9d-bae1-00310cfef38a	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	BONJOUR	\N	\N	f	f	2026-05-06 09:59:07.918855	2026-05-06 09:59:07.918855	\N	\N	f	t
56241e77-5f6c-4fa8-a358-508ce435333c	46232cc4-6777-4a9d-bae1-00310cfef38a	31100824-069e-4aa2-90fd-3a56ea6ad20a	JJ	\N	\N	f	f	2026-05-06 10:00:12.362134	2026-05-06 10:00:12.362134	\N	\N	f	t
2232bb71-45f6-4df4-948d-685dfcf0cb32	90cc54ac-55c2-4b94-96f1-ef9e9ab90cff	dce21297-ed4d-44bf-955c-cfe7517c2959	Groupe "GP" créé	\N	\N	f	f	2026-06-19 21:27:10.432149	2026-06-19 21:27:10.432149	\N	\N	t	f
8fba9ce8-58ad-42f7-83bd-159482c2dcdc	90cc54ac-55c2-4b94-96f1-ef9e9ab90cff	dce21297-ed4d-44bf-955c-cfe7517c2959	co	\N	\N	f	f	2026-06-19 21:27:38.913127	2026-06-19 21:27:38.913127	\N	\N	f	f
8b02599f-322f-4d22-a246-b402220a9fcc	46232cc4-6777-4a9d-bae1-00310cfef38a	31100824-069e-4aa2-90fd-3a56ea6ad20a	wkamga a quitté le groupe	\N	\N	f	f	2026-05-07 10:55:07.087917	2026-05-07 10:55:07.087917	\N	\N	t	f
\.


--
-- TOC entry 5203 (class 0 OID 16557)
-- Dependencies: 227
-- Data for Name: groups; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.groups (id, name, description, type, created_by, is_private, created_at, pinned_message_id) FROM stdin;
46232cc4-6777-4a9d-bae1-00310cfef38a	AA	\N	custom	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	f	2026-05-06 09:58:57.528311	\N
c7886fb9-c0ac-4bd3-a8ec-0e834d07c7e1	K	\N	custom	31100824-069e-4aa2-90fd-3a56ea6ad20a	f	2026-05-07 13:21:44.846861	\N
c177b8b9-29db-4c2e-99d9-866cf352313f	R	\N	custom	31100824-069e-4aa2-90fd-3a56ea6ad20a	f	2026-05-07 13:30:28.726195	\N
6bacd8af-10a1-4864-b1cd-7c80fd8a273a	E	\N	custom	31100824-069e-4aa2-90fd-3a56ea6ad20a	f	2026-05-07 13:40:05.794818	\N
90cc54ac-55c2-4b94-96f1-ef9e9ab90cff	GP	c'est nous	custom	dce21297-ed4d-44bf-955c-cfe7517c2959	f	2026-06-19 21:27:10.432149	\N
\.


--
-- TOC entry 5198 (class 0 OID 16441)
-- Dependencies: 222
-- Data for Name: likes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.likes (id, user_id, post_id, created_at) FROM stdin;
e03c7780-6738-4b73-bd53-f79a70a8afb2	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	94433f30-2260-4a88-80fe-33c41673d0d8	2026-05-06 08:52:56.961249
d2ccb5dd-94bc-440c-bf27-aad8af099dd7	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	94433f30-2260-4a88-80fe-33c41673d0d8	2026-05-06 09:05:04.418075
d535ecc7-d256-45ea-9197-7316b17dfebd	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	b2490b1e-c41f-4eed-8f99-7b11da9eb11c	2026-05-06 09:55:51.498696
5c9568c7-3b11-4b31-8867-7c4d08586520	31100824-069e-4aa2-90fd-3a56ea6ad20a	b2490b1e-c41f-4eed-8f99-7b11da9eb11c	2026-05-06 10:13:16.993083
3ac4bbf7-c797-41de-ae28-8c7ed96c9a18	dce21297-ed4d-44bf-955c-cfe7517c2959	e7dcf2ff-7d35-448f-adea-a3ea622bd9aa	2026-06-19 22:30:38.141459
\.


--
-- TOC entry 5202 (class 0 OID 16532)
-- Dependencies: 226
-- Data for Name: messages; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.messages (id, sender_id, receiver_id, content, is_edited, is_deleted, is_read, created_at, updated_at, file_url, file_type, file_name, file_size) FROM stdin;
dc187305-e2b4-4e44-aa35-de3182043561	31100824-069e-4aa2-90fd-3a56ea6ad20a	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	Bonjour bro	f	f	t	2026-04-26 20:30:53.485796	2026-04-26 20:35:52.482518	\N	\N	\N	\N
d8da43ea-a233-4aea-8787-e14eae31e8db	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	31100824-069e-4aa2-90fd-3a56ea6ad20a	yo	f	f	t	2026-04-26 20:42:54.808893	2026-04-26 20:44:48.9197	\N	\N	\N	\N
c1f4112b-22d0-441f-82ba-6d069b3104f3	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	31100824-069e-4aa2-90fd-3a56ea6ad20a	quoi de neuf	f	f	t	2026-04-26 20:43:09.706725	2026-04-26 20:44:48.933781	\N	\N	\N	\N
7b0e3845-b4c4-4b70-9648-ed5bff7008d3	31100824-069e-4aa2-90fd-3a56ea6ad20a	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	\N	f	f	t	2026-04-26 21:50:26.740771	2026-04-26 21:52:53.334177	/uploads/media-1777236626704-755265888	document	file_1777236626444	423119
271bc5b2-7543-4c6e-bfbe-9eb77c58a555	31100824-069e-4aa2-90fd-3a56ea6ad20a	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	\N	f	f	t	2026-04-26 21:51:05.784922	2026-04-26 21:52:53.540953	/uploads/media-1777236665557-198690334	document	file_1777236665102	535476
1f6bb0d9-4254-43e9-927d-a610d3273b54	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	31100824-069e-4aa2-90fd-3a56ea6ad20a	Voici mon cer	f	f	t	2026-04-26 22:07:30.705884	2026-04-26 22:08:22.580067	/uploads/media-1777237650521-410316461	document	file_1777237650065	436205
729df360-737a-4d0d-af68-17e57702a781	31100824-069e-4aa2-90fd-3a56ea6ad20a	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	K	f	f	t	2026-04-26 22:30:02.034869	2026-04-27 07:14:12.279309	/uploads/media-1777239001898-863403582	document	file_1777239001781	436205
6f3d41b1-d7d6-4029-807c-23840c71c843	31100824-069e-4aa2-90fd-3a56ea6ad20a	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	\N	f	f	t	2026-04-27 07:02:53.719361	2026-04-27 07:14:12.36392	/uploads/media-1777269773574-629968027.pdf	document	CER - SAN TO HYPERCONVERGED INFRASTRUCTURE TOFA DEFFO.pdf	535476
cb17c0ef-b652-4123-8ec5-18c4d01bd92a	31100824-069e-4aa2-90fd-3a56ea6ad20a	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	beau	f	f	t	2026-04-27 07:12:37.176192	2026-04-27 07:14:12.367458	/uploads/media-1777270357044-660839322.jpg	image	scaled_wp2858551.jpg	499496
2cc17bb9-13b1-43f0-a8b8-0c71a41daed9	31100824-069e-4aa2-90fd-3a56ea6ad20a	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	\N	f	f	t	2026-04-27 06:54:33.642404	2026-04-27 07:14:12.379831	/uploads/media-1777269273521-236606951	document	file_1777269273406	535476
1ede6438-e3de-4761-8e09-b6c209243379	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	31100824-069e-4aa2-90fd-3a56ea6ad20a	JJ	f	f	t	2026-04-27 09:47:52.434376	2026-04-27 09:48:36.609305	\N	\N	\N	\N
a1d2710e-ab85-46a7-837d-078bf9c7c578	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	31100824-069e-4aa2-90fd-3a56ea6ad20a	??	f	f	t	2026-04-27 12:33:58.297274	2026-04-27 12:35:11.234614	/uploads/media-1777289638186-118817403.jpg	image	scaled_wp2858551.jpg	499496
450f7d64-18a7-46ba-a6f6-607c4c2dadb2	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	31100824-069e-4aa2-90fd-3a56ea6ad20a	Voici mon CER	f	f	t	2026-04-27 12:34:34.014159	2026-04-27 12:35:11.298284	/uploads/media-1777289673873-322084689.pdf	document	CER_DATACENTER TOFA DEFFO.pdf	436205
b64e2d47-725d-430e-867d-f74afdadefcd	31100824-069e-4aa2-90fd-3a56ea6ad20a	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	D	f	f	t	2026-04-27 13:10:07.64364	2026-04-27 14:48:38.761981	/uploads/media-1777291807467-971212369.jpg	image	scaled_wp2858551.jpg	499496
9c0f9684-d799-4cad-8b78-824301e67ba0	31100824-069e-4aa2-90fd-3a56ea6ad20a	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	S	f	f	t	2026-04-27 13:10:34.000291	2026-04-27 14:48:38.857458	/uploads/media-1777291833848-913753853.pdf	document	CER_DATACENTER TOFA DEFFO.pdf	436205
27416bc6-3adc-4f57-ab25-1e85f34d351b	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	31100824-069e-4aa2-90fd-3a56ea6ad20a	RR	f	f	t	2026-04-27 14:51:57.422145	2026-04-27 14:53:11.240228	/uploads/media-1777297917297-908651023.jpg	image	scaled_wp2858551.jpg	499496
a85835f9-7798-4320-abb3-48760d0f66d1	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	31100824-069e-4aa2-90fd-3a56ea6ad20a	\N	f	f	t	2026-04-27 14:55:21.210494	2026-04-27 15:05:55.7375	/uploads/media-1777298121092-560063602.pdf	document	CER_DATACENTER TOFA DEFFO.pdf	436205
ca446219-19d6-4465-8c5d-d735b6901b30	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	31100824-069e-4aa2-90fd-3a56ea6ad20a	\N	f	f	t	2026-04-27 14:55:44.520774	2026-04-27 15:05:55.818094	/uploads/media-1777298144422-801767429.jpg	image	scaled_wp2858551.jpg	499496
81a30047-024c-4415-9886-fa90409dcb01	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	31100824-069e-4aa2-90fd-3a56ea6ad20a	ss	f	f	t	2026-04-27 15:05:19.444836	2026-04-27 15:05:55.828417	/uploads/media-1777298719252-575170359.jpg	image	scaled_wp2858551.jpg	499496
f9d80c50-8f81-45be-bfec-b1241ed9b5ac	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	31100824-069e-4aa2-90fd-3a56ea6ad20a	dd	f	f	t	2026-04-27 15:05:02.269831	2026-04-27 15:05:56.049316	\N	\N	\N	\N
7c9e519f-bcd6-4aff-996c-466db04ad9f7	31100824-069e-4aa2-90fd-3a56ea6ad20a	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	kdk	f	f	t	2026-04-29 11:56:32.546244	2026-05-06 08:46:45.914442	\N	\N	\N	\N
f081c121-0a76-4050-85d9-f16f97038fb9	31100824-069e-4aa2-90fd-3a56ea6ad20a	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	jj	f	f	t	2026-04-28 06:57:08.91279	2026-05-06 09:06:16.060318	\N	\N	\N	\N
9b8d1f7b-7816-45a9-8d1a-417328f9eac4	31100824-069e-4aa2-90fd-3a56ea6ad20a	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	kkk	f	f	t	2026-04-27 22:07:44.008139	2026-05-06 09:06:16.059406	\N	\N	\N	\N
d84f5f71-2d7f-4c3c-af3a-0bffe47b6b70	31100824-069e-4aa2-90fd-3a56ea6ad20a	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	CHC	f	f	t	2026-04-29 12:56:48.949939	2026-05-06 09:06:16.069112	\N	\N	\N	\N
d8a8223c-f058-4fca-b5bf-26ba0825780e	31100824-069e-4aa2-90fd-3a56ea6ad20a	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	DJ	f	f	t	2026-04-29 12:57:03.598862	2026-05-06 09:06:16.070129	/uploads/media-1777463823458-223977641.jpg	image	scaled_wp2858551.jpg	499496
ff82159a-2c20-40d5-9784-a3dcdcf9ec34	31100824-069e-4aa2-90fd-3a56ea6ad20a	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	\N	f	f	t	2026-04-29 13:00:04.57143	2026-05-06 09:06:16.157679	/uploads/media-1777464004455-53299186.pdf	document	CER_DATACENTER TOFA DEFFO.pdf	436205
0a0edab3-403a-4535-981d-2432922fd5fc	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	31100824-069e-4aa2-90fd-3a56ea6ad20a	c	f	f	t	2026-05-06 09:50:15.477564	2026-05-06 09:52:40.951794	\N	\N	\N	\N
430bb0cd-6052-4673-bbfa-388b31d23c8c	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	31100824-069e-4aa2-90fd-3a56ea6ad20a	mp	f	f	t	2026-05-06 17:16:03.229881	2026-05-07 10:22:34.841682	\N	\N	\N	\N
2fc829b1-e2d6-47e3-9163-36075034517f	31100824-069e-4aa2-90fd-3a56ea6ad20a	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	CJD	f	f	f	2026-05-07 10:47:00.383547	2026-05-07 10:47:00.383547	\N	\N	\N	\N
e61d6eb6-3d6e-4c48-ad0f-a11bf9c21c62	31100824-069e-4aa2-90fd-3a56ea6ad20a	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	s	f	f	f	2026-05-07 13:11:16.873235	2026-05-07 13:11:16.873235	\N	\N	\N	\N
6df808b9-acf6-4447-a7f1-c35574d9610b	dce21297-ed4d-44bf-955c-cfe7517c2959	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	KD	f	f	f	2026-06-19 22:41:06.497474	2026-06-19 22:41:06.497474	\N	\N	\N	\N
\.


--
-- TOC entry 5206 (class 0 OID 16621)
-- Dependencies: 230
-- Data for Name: notifications; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.notifications (id, user_id, type, content, is_read, reference_id, created_at) FROM stdin;
5f87c450-5b8f-4f7a-9330-62c185790d39	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	new_follower	willy kamga a commencé à vous suivre.	f	31100824-069e-4aa2-90fd-3a56ea6ad20a	2026-04-26 21:24:21.198
2ad4adc0-6f3c-4821-8979-76b8ab7cc4b6	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	new_follower	Onana Marc a commencé à vous suivre.	f	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	2026-04-27 12:33:18.686
021a9f12-4ba6-48cd-95db-c6d22030c6be	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	like	Onana Marc a aimé votre publication.	f	94433f30-2260-4a88-80fe-33c41673d0d8	2026-05-06 09:05:04.436
aac8db56-6485-41c5-bf3a-9fc02eab9ddf	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	comment	Onana Marc a commenté votre publication.	f	94433f30-2260-4a88-80fe-33c41673d0d8	2026-05-06 09:05:10.497
09031599-5d5d-484b-bb26-3f849a074add	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	new_follower	willy kamga a commencé à vous suivre.	t	31100824-069e-4aa2-90fd-3a56ea6ad20a	2026-04-28 14:10:20.877
806271aa-4a5c-4f4d-9bd0-3c45aa80fc02	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	new_follower	willy kamga a commencé à vous suivre.	t	31100824-069e-4aa2-90fd-3a56ea6ad20a	2026-04-28 14:07:48.767
95a2a011-2839-46bb-8e6b-859f6fa52985	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	new_follower	willy kamga a commencé à vous suivre.	t	31100824-069e-4aa2-90fd-3a56ea6ad20a	2026-04-28 09:02:26.226
64d4009b-c68d-464c-a237-883572e2746b	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	new_follower	Onana Marc a commencé à vous suivre.	f	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	2026-05-06 09:49:55.946
c7b241fb-d0db-411a-8944-6123ab87fc37	31100824-069e-4aa2-90fd-3a56ea6ad20a	new_follower	David Maza a commencé à vous suivre.	t	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	2026-04-26 21:25:33.91
53172cb2-1c80-4bd6-bd28-b6717eb2ea4d	31100824-069e-4aa2-90fd-3a56ea6ad20a	new_follower	Onana Marc a commencé à vous suivre.	t	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	2026-05-06 09:05:44.7
8f68839d-b8ba-4d5a-a032-24cf70f2cedb	31100824-069e-4aa2-90fd-3a56ea6ad20a	new_follower	Onana Marc a commencé à vous suivre.	t	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	2026-05-06 09:50:06.398
ce15f6bd-abcf-40d5-94bc-b411e5deccb9	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	new_follower	willy kamga a commencé à vous suivre.	f	31100824-069e-4aa2-90fd-3a56ea6ad20a	2026-05-06 09:54:36.541
0ba397e6-0662-4087-88c8-6f7c1986f896	31100824-069e-4aa2-90fd-3a56ea6ad20a	new_follower	David Maza a commencé à vous suivre.	f	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	2026-05-06 09:55:34.014
d079c1f9-a95c-46d3-bf3b-ebab4b97920d	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	new_follower	David Maza a commencé à vous suivre.	f	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	2026-05-06 09:55:45.378
8e3cf0e7-e465-4af1-bead-e7965795b441	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	like	David Maza a aimé votre publication.	f	b2490b1e-c41f-4eed-8f99-7b11da9eb11c	2026-05-06 09:55:51.504
8e609a72-ad9a-42ad-ab80-95ae327bc461	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	comment	David Maza a commenté votre publication.	f	b2490b1e-c41f-4eed-8f99-7b11da9eb11c	2026-05-06 09:56:00.9
c94b993f-46ce-4b56-84f5-a797a86b28c1	31100824-069e-4aa2-90fd-3a56ea6ad20a	group_invite	OMarc vous a ajouté au groupe "AA"	f	46232cc4-6777-4a9d-bae1-00310cfef38a	2026-05-06 09:58:57.728
0fe4b75d-7cb8-4750-8891-ccd05d4675e1	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	comment	willy kamga a commenté votre publication.	t	b2490b1e-c41f-4eed-8f99-7b11da9eb11c	2026-05-06 10:13:29.276
0fb0d1ee-6300-4807-abf2-04d7e50ed4ea	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	like	willy kamga a aimé votre publication.	t	b2490b1e-c41f-4eed-8f99-7b11da9eb11c	2026-05-06 10:13:17.016
a09f0cd7-4d80-4cc0-815d-371fde39858f	31100824-069e-4aa2-90fd-3a56ea6ad20a	group_invite	mdavid vous a ajouté au groupe "NEW"	f	e1276c4d-7472-40a6-bdf1-71ac50d4043c	2026-05-07 10:49:34.031
234ffe1e-69a2-4b62-a3d3-78c51dab9dd9	31100824-069e-4aa2-90fd-3a56ea6ad20a	group_invite	mdavid vous a ajouté au groupe "NEW"	f	e1276c4d-7472-40a6-bdf1-71ac50d4043c	2026-05-07 10:50:01.133
54ef04d9-e22e-4fc4-a72f-d72bf0cb599e	31100824-069e-4aa2-90fd-3a56ea6ad20a	group_invite	mdavid vous a ajouté au groupe "NEW"	f	e1276c4d-7472-40a6-bdf1-71ac50d4043c	2026-05-07 10:51:01.903
8f88adb4-dac4-4a0a-a4d0-015b57b04c82	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	group_invite	wkamga vous a ajouté au groupe "F"	f	0831c18e-d285-4ed8-8f5c-93679017d6e1	2026-05-07 11:03:28.362
47526c36-b714-4197-9f27-fb01c8f72e7e	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	group_invite	wkamga vous a ajouté au groupe "F"	f	0831c18e-d285-4ed8-8f5c-93679017d6e1	2026-05-07 11:03:28.365
679e959d-2274-45f2-9195-b32b5543eea6	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	group_invite	wkamga vous a ajouté au groupe "D"	f	3a4c4ef6-a52a-4043-8b78-b1e2da9f65e5	2026-05-07 11:15:57.86
a9bc2db3-7e57-4cf2-93f4-9a164b4b5b88	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	group_invite	wkamga vous a ajouté au groupe "D"	f	3a4c4ef6-a52a-4043-8b78-b1e2da9f65e5	2026-05-07 11:16:31.682
6123dc6b-6d22-41d6-9864-a600dcc5c387	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	group_invite	wkamga vous a ajouté au groupe "D"	f	45b6511a-ad53-489e-9dd6-332259a6db06	2026-05-07 12:25:16.327
9b504166-129d-4122-986b-86db06a9be40	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	group_invite	wkamga vous a ajouté au groupe "D"	f	45b6511a-ad53-489e-9dd6-332259a6db06	2026-05-07 12:25:16.329
ea9de21b-5477-477b-a9ca-aa04861aae12	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	group_invite	wkamga vous a ajouté au groupe "FG"	f	0ad1799b-44f5-4ac4-b76c-05af51daa666	2026-05-07 13:06:06.455
9102cdeb-e8d7-4e74-9e03-2cb112ad30b2	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	group_invite	wkamga vous a ajouté au groupe "FG"	f	0ad1799b-44f5-4ac4-b76c-05af51daa666	2026-05-07 13:06:06.458
6920e0ad-2d44-443d-9a3e-57cca462ac21	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	group_invite	wkamga vous a ajouté au groupe "K"	f	c7886fb9-c0ac-4bd3-a8ec-0e834d07c7e1	2026-05-07 13:21:44.954
10e2c77e-587d-4b61-b83d-58bc33d18f1b	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	group_invite	wkamga vous a ajouté au groupe "R"	f	c177b8b9-29db-4c2e-99d9-866cf352313f	2026-05-07 13:30:28.826
1af4e213-03fc-4bcf-b654-1d925a5cc5bd	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	group_invite	wkamga vous a ajouté au groupe "E"	f	6bacd8af-10a1-4864-b1cd-7c80fd8a273a	2026-05-07 13:40:05.907
cc3e9344-dc54-45d3-aa30-9c07b63068d0	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	group_invite	DokoWM vous a ajouté au groupe "GP"	f	90cc54ac-55c2-4b94-96f1-ef9e9ab90cff	2026-06-19 21:27:10.594
cb94bd4c-28d6-470f-ad97-0d5c786f0097	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	group_invite	DokoWM vous a ajouté au groupe "GP"	f	90cc54ac-55c2-4b94-96f1-ef9e9ab90cff	2026-06-19 21:27:10.598
c4614835-05b6-4d0c-9b86-bda8c1752077	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	like	William DoKo a aimé votre publication.	f	b2490b1e-c41f-4eed-8f99-7b11da9eb11c	2026-06-19 21:42:52.926
06f3fbf8-e6c5-4b5d-a545-d3127f92c7c0	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	new_follower	William DoKo a commencé à vous suivre.	f	dce21297-ed4d-44bf-955c-cfe7517c2959	2026-06-19 22:29:20.435
\.


--
-- TOC entry 5197 (class 0 OID 16422)
-- Dependencies: 221
-- Data for Name: posts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.posts (id, user_id, content, media_url, media_type, media_size, tags, is_institutional, is_deleted, created_at, updated_at, media_gallery) FROM stdin;
94433f30-2260-4a88-80fe-33c41673d0d8	b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	jsj	/uploads/media-1778053968105-500814015.jpg	photo	251677	{#ucac-icam}	f	f	2026-05-06 08:52:48.246772	2026-05-06 08:52:48.246772	["/uploads/media-1778053968105-500814015.jpg"]
b2490b1e-c41f-4eed-8f99-7b11da9eb11c	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	well	/uploads/media-1778057485376-859143707.jpg	photo	251677	{#info}	f	f	2026-05-06 09:51:25.534774	2026-05-06 09:51:25.534774	["/uploads/media-1778057485376-859143707.jpg"]
e7dcf2ff-7d35-448f-adea-a3ea622bd9aa	dce21297-ed4d-44bf-955c-cfe7517c2959	recherche de stage	/uploads/media-1781904616168-608524225.jpg	photo	18307	{#stage}	f	f	2026-06-19 22:30:16.239252	2026-06-19 22:30:16.239252	["/uploads/media-1781904616168-608524225.jpg"]
\.


--
-- TOC entry 5201 (class 0 OID 16504)
-- Dependencies: 225
-- Data for Name: reports; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.reports (id, reporter_id, post_id, comment_id, reason, status, created_at) FROM stdin;
e9f74e0d-25a4-4cfa-9886-575829cc93d8	293e1ebd-0e43-47d1-b3bc-a5448e2b6828	b2490b1e-c41f-4eed-8f99-7b11da9eb11c	\N	Harcèlement	pending	2026-05-06 10:17:34.575606
\.


--
-- TOC entry 5207 (class 0 OID 16639)
-- Dependencies: 231
-- Data for Name: sessions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.sessions (id, user_id, token, device_info, is_active, created_at, expires_at) FROM stdin;
\.


--
-- TOC entry 5196 (class 0 OID 16400)
-- Dependencies: 220
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (id, username, email, password_hash, full_name, bio, avatar_url, role, promotion, residence, filiere, is_active, is_verified, created_at, updated_at) FROM stdin;
b4b53303-4ae6-41dd-9fbc-f397fb0d3d70	mdavid	david.maza@ucac-icam.com	$2b$10$3nRjdR7pRhAL3PKlQU1utuhtJusho07NZ.v5qvKMo62R9hXqtikXm	David Maza	\N	\N	student	X2029	Minicité C	Génie Informatique	t	f	2026-04-26 19:44:29.936228	2026-04-26 19:44:29.936228
293e1ebd-0e43-47d1-b3bc-a5448e2b6828	OMarc	marc.onana@ucac-icam.com	$2b$10$GPk9/JaS/N.svFuVUxgN6.PRhmu3MLFC6dC5l5E3gtlmZh9hX3xQC	Onana Marc	\N	\N	student	X2026	Hors campus	Génie Informatique	t	f	2026-04-27 12:32:49.988059	2026-04-27 12:32:49.988059
31100824-069e-4aa2-90fd-3a56ea6ad20a	wkamga	willy.kamga@ucac-icam.com	$2b$10$QLwMR1Oxv6fitbtTefNDDueQPVFolqyphnY69QwdANJ9HgiTs.vi6	willy kamga	\N	/uploads/media-1777380986279-977408617.jpg	student	X2026	Minicité C	Génie Informatique	t	f	2026-04-26 19:53:23.699057	2026-04-28 13:56:26.503064
dce21297-ed4d-44bf-955c-cfe7517c2959	DokoWM	doko.william@2030.ucac-icam.com	$2b$10$PKcdwkuLWoOcmij860mGdeWUfjPD4wak5lq3kE3t2FpM.sBLq5hPe	William DoKo	\N	/uploads/media-1781904576210-585317844.jpg	student	X2030	Minicité C	Génie Informatique	t	f	2026-06-19 21:25:54.247522	2026-06-19 22:29:36.30302
\.


--
-- TOC entry 5017 (class 2606 OID 16692)
-- Name: comment_likes comment_likes_comment_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.comment_likes
    ADD CONSTRAINT comment_likes_comment_id_user_id_key UNIQUE (comment_id, user_id);


--
-- TOC entry 5019 (class 2606 OID 16690)
-- Name: comment_likes comment_likes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.comment_likes
    ADD CONSTRAINT comment_likes_pkey PRIMARY KEY (id);


--
-- TOC entry 4988 (class 2606 OID 16473)
-- Name: comments comments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_pkey PRIMARY KEY (id);


--
-- TOC entry 4991 (class 2606 OID 16493)
-- Name: follows follows_follower_id_following_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.follows
    ADD CONSTRAINT follows_follower_id_following_id_key UNIQUE (follower_id, following_id);


--
-- TOC entry 4993 (class 2606 OID 16491)
-- Name: follows follows_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.follows
    ADD CONSTRAINT follows_pkey PRIMARY KEY (id);


--
-- TOC entry 5005 (class 2606 OID 16587)
-- Name: group_members group_members_group_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.group_members
    ADD CONSTRAINT group_members_group_id_user_id_key UNIQUE (group_id, user_id);


--
-- TOC entry 5007 (class 2606 OID 16585)
-- Name: group_members group_members_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.group_members
    ADD CONSTRAINT group_members_pkey PRIMARY KEY (id);


--
-- TOC entry 5009 (class 2606 OID 16610)
-- Name: group_messages group_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.group_messages
    ADD CONSTRAINT group_messages_pkey PRIMARY KEY (id);


--
-- TOC entry 5003 (class 2606 OID 16570)
-- Name: groups groups_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT groups_pkey PRIMARY KEY (id);


--
-- TOC entry 4984 (class 2606 OID 16448)
-- Name: likes likes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.likes
    ADD CONSTRAINT likes_pkey PRIMARY KEY (id);


--
-- TOC entry 4986 (class 2606 OID 16450)
-- Name: likes likes_user_id_post_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.likes
    ADD CONSTRAINT likes_user_id_post_id_key UNIQUE (user_id, post_id);


--
-- TOC entry 5001 (class 2606 OID 16546)
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- TOC entry 5013 (class 2606 OID 16633)
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- TOC entry 4981 (class 2606 OID 16435)
-- Name: posts posts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_pkey PRIMARY KEY (id);


--
-- TOC entry 4997 (class 2606 OID 16516)
-- Name: reports reports_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_pkey PRIMARY KEY (id);


--
-- TOC entry 5015 (class 2606 OID 16651)
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- TOC entry 4973 (class 2606 OID 16421)
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- TOC entry 4975 (class 2606 OID 16417)
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- TOC entry 4977 (class 2606 OID 16419)
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- TOC entry 5020 (class 1259 OID 16703)
-- Name: idx_comment_likes_comment_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_comment_likes_comment_id ON public.comment_likes USING btree (comment_id);


--
-- TOC entry 5021 (class 1259 OID 16704)
-- Name: idx_comment_likes_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_comment_likes_user_id ON public.comment_likes USING btree (user_id);


--
-- TOC entry 4989 (class 1259 OID 16660)
-- Name: idx_comments_post_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_comments_post_id ON public.comments USING btree (post_id);


--
-- TOC entry 4994 (class 1259 OID 16661)
-- Name: idx_follows_follower; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_follows_follower ON public.follows USING btree (follower_id);


--
-- TOC entry 4995 (class 1259 OID 16662)
-- Name: idx_follows_following; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_follows_following ON public.follows USING btree (following_id);


--
-- TOC entry 5010 (class 1259 OID 16665)
-- Name: idx_group_messages_group; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_group_messages_group ON public.group_messages USING btree (group_id);


--
-- TOC entry 4982 (class 1259 OID 16659)
-- Name: idx_likes_post_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_likes_post_id ON public.likes USING btree (post_id);


--
-- TOC entry 4998 (class 1259 OID 16664)
-- Name: idx_messages_receiver; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_messages_receiver ON public.messages USING btree (receiver_id);


--
-- TOC entry 4999 (class 1259 OID 16663)
-- Name: idx_messages_sender; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_messages_sender ON public.messages USING btree (sender_id);


--
-- TOC entry 5011 (class 1259 OID 16666)
-- Name: idx_notifications_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_notifications_user ON public.notifications USING btree (user_id);


--
-- TOC entry 4978 (class 1259 OID 16658)
-- Name: idx_posts_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_posts_created_at ON public.posts USING btree (created_at DESC);


--
-- TOC entry 4979 (class 1259 OID 16657)
-- Name: idx_posts_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_posts_user_id ON public.posts USING btree (user_id);


--
-- TOC entry 5047 (class 2620 OID 16670)
-- Name: comments set_timestamp; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_timestamp BEFORE UPDATE ON public.comments FOR EACH ROW EXECUTE FUNCTION public.trigger_set_timestamp();


--
-- TOC entry 5048 (class 2620 OID 16671)
-- Name: messages set_timestamp; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_timestamp BEFORE UPDATE ON public.messages FOR EACH ROW EXECUTE FUNCTION public.trigger_set_timestamp();


--
-- TOC entry 5046 (class 2620 OID 16669)
-- Name: posts set_timestamp; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_timestamp BEFORE UPDATE ON public.posts FOR EACH ROW EXECUTE FUNCTION public.trigger_set_timestamp();


--
-- TOC entry 5045 (class 2620 OID 16668)
-- Name: users set_timestamp; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_timestamp BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.trigger_set_timestamp();


--
-- TOC entry 5043 (class 2606 OID 16693)
-- Name: comment_likes comment_likes_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.comment_likes
    ADD CONSTRAINT comment_likes_comment_id_fkey FOREIGN KEY (comment_id) REFERENCES public.comments(id) ON DELETE CASCADE;


--
-- TOC entry 5044 (class 2606 OID 16698)
-- Name: comment_likes comment_likes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.comment_likes
    ADD CONSTRAINT comment_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 5025 (class 2606 OID 16676)
-- Name: comments comments_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.comments(id) ON DELETE CASCADE;


--
-- TOC entry 5026 (class 2606 OID 16479)
-- Name: comments comments_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- TOC entry 5027 (class 2606 OID 16474)
-- Name: comments comments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 5028 (class 2606 OID 16494)
-- Name: follows follows_follower_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.follows
    ADD CONSTRAINT follows_follower_id_fkey FOREIGN KEY (follower_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 5029 (class 2606 OID 16499)
-- Name: follows follows_following_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.follows
    ADD CONSTRAINT follows_following_id_fkey FOREIGN KEY (following_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 5037 (class 2606 OID 16588)
-- Name: group_members group_members_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.group_members
    ADD CONSTRAINT group_members_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;


--
-- TOC entry 5038 (class 2606 OID 16593)
-- Name: group_members group_members_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.group_members
    ADD CONSTRAINT group_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 5039 (class 2606 OID 16611)
-- Name: group_messages group_messages_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.group_messages
    ADD CONSTRAINT group_messages_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;


--
-- TOC entry 5040 (class 2606 OID 16616)
-- Name: group_messages group_messages_sender_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.group_messages
    ADD CONSTRAINT group_messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 5035 (class 2606 OID 16571)
-- Name: groups groups_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT groups_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5036 (class 2606 OID 16706)
-- Name: groups groups_pinned_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT groups_pinned_message_id_fkey FOREIGN KEY (pinned_message_id) REFERENCES public.group_messages(id) ON DELETE SET NULL;


--
-- TOC entry 5023 (class 2606 OID 16456)
-- Name: likes likes_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.likes
    ADD CONSTRAINT likes_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- TOC entry 5024 (class 2606 OID 16451)
-- Name: likes likes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.likes
    ADD CONSTRAINT likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 5033 (class 2606 OID 16552)
-- Name: messages messages_receiver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_receiver_id_fkey FOREIGN KEY (receiver_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 5034 (class 2606 OID 16547)
-- Name: messages messages_sender_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 5041 (class 2606 OID 16634)
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 5022 (class 2606 OID 16436)
-- Name: posts posts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 5030 (class 2606 OID 16527)
-- Name: reports reports_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_comment_id_fkey FOREIGN KEY (comment_id) REFERENCES public.comments(id) ON DELETE SET NULL;


--
-- TOC entry 5031 (class 2606 OID 16522)
-- Name: reports reports_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE SET NULL;


--
-- TOC entry 5032 (class 2606 OID 16517)
-- Name: reports reports_reporter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_reporter_id_fkey FOREIGN KEY (reporter_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 5042 (class 2606 OID 16652)
-- Name: sessions sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


-- Completed on 2026-06-22 08:17:13

--
-- PostgreSQL database dump complete
--


