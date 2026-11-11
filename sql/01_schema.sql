-- ================================================================
--  Esquema de la base de datos (solo estructura, sin datos)
--  Generado con pg_restore --schema-only a partir del esquema original.
--  Incluye tablas, secuencias de folios, funciones PL/pgSQL y triggers.
-- ================================================================
--
-- PostgreSQL database dump
--

\restrict 0IB7hlcU5Qdh1dK7lS1qyKiKAqv3dSrK8Yu4CSUyq6lXgCL8tASd1NKBXTM8VPA


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
-- Name: entrega_estatus; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.entrega_estatus AS ENUM (
    'ENTREGADO',
    'CANCELADO'
);


--
-- Name: fn_end_of_month_deadline(timestamp without time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_end_of_month_deadline(p_base timestamp without time zone) RETURNS timestamp without time zone
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT (date_trunc('month', p_base) + interval '1 month' - interval '1 second')::timestamp;
$$;


--
-- Name: fn_expedientes_entrega_auto_populate(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_expedientes_entrega_auto_populate() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Auto-poblar dependencia desde dgeneral.dependencia
  IF NEW.id_dgeneral IS NOT NULL THEN
    SELECT dependencia INTO NEW.dependencia FROM dgeneral WHERE id = NEW.id_dgeneral;
  END IF;

  -- Auto-poblar concepto desde partidas.descripcion
  IF NEW.partida_clave IS NOT NULL THEN
    SELECT descripcion INTO NEW.concepto FROM partidas WHERE clave = NEW.partida_clave;
  END IF;

  -- Auto-poblar importe desde devengados.total
  IF NEW.id_devengado IS NOT NULL THEN
    SELECT total INTO NEW.importe FROM devengados WHERE id = NEW.id_devengado;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: fn_mes_pago_to_date(text, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_mes_pago_to_date(p_mes text, p_ref date DEFAULT CURRENT_DATE) RETURNS date
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
  v text;
  v_year int;
  v_month int;
BEGIN
  IF p_mes IS NULL OR TRIM(p_mes) = '' THEN
    RETURN NULL;
  END IF;

  v := UPPER(TRIM(p_mes));
  v := TRANSLATE(v, 'ÁÉÍÓÚÜáéíóúü', 'AEIOUUAEIOUU');

  IF v ~ '^\d{4}-\d{2}-\d{2}$' THEN
    RETURN date_trunc('month', v::date)::date;
  ELSIF v ~ '^\d{4}-\d{2}$' THEN
    RETURN date_trunc('month', (v || '-01')::date)::date;
  END IF;

  v_year := COALESCE(EXTRACT(YEAR FROM p_ref)::int, EXTRACT(YEAR FROM current_date)::int);

  IF v = 'ENERO' THEN v_month := 1;
  ELSIF v = 'FEBRERO' THEN v_month := 2;
  ELSIF v = 'MARZO' THEN v_month := 3;
  ELSIF v = 'ABRIL' THEN v_month := 4;
  ELSIF v = 'MAYO' THEN v_month := 5;
  ELSIF v = 'JUNIO' THEN v_month := 6;
  ELSIF v = 'JULIO' THEN v_month := 7;
  ELSIF v = 'AGOSTO' THEN v_month := 8;
  ELSIF v = 'SEPTIEMBRE' OR v = 'SETIEMBRE' THEN v_month := 9;
  ELSIF v = 'OCTUBRE' THEN v_month := 10;
  ELSIF v = 'NOVIEMBRE' THEN v_month := 11;
  ELSIF v = 'DICIEMBRE' THEN v_month := 12;
  ELSE
    RETURN NULL;
  END IF;

  RETURN make_date(v_year, v_month, 1);
END;
$_$;


--
-- Name: fn_next_folio_comprometido(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_next_folio_comprometido() RETURNS integer
    LANGUAGE sql
    AS $$
  SELECT nextval('seq_comprometido_folio')::integer;
$$;


--
-- Name: fn_next_folio_devengado(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_next_folio_devengado() RETURNS integer
    LANGUAGE sql
    AS $$
  SELECT nextval('seq_devengado_folio')::integer;
$$;


--
-- Name: fn_next_folio_reconduccion(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_next_folio_reconduccion() RETURNS integer
    LANGUAGE sql
    AS $$
  SELECT nextval('seq_reconduccion_folio')::integer;
$$;


--
-- Name: fn_next_folio_suficiencia(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_next_folio_suficiencia() RETURNS integer
    LANGUAGE sql
    AS $$
  SELECT nextval('seq_suficiencia_folio')::integer;
$$;


--
-- Name: fn_recalcular_aggreg_presupuesto(character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_recalcular_aggreg_presupuesto(p_idproyecto character varying, p_partida character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Asegura existencia del registro
  INSERT INTO public.presupuesto_detalle (idProyecto, partida, presupuesto, total_gastado, total_reconducido, saldo_disponible)
  SELECT p_idProyecto, p_partida, 0, 0, 0, 0
  WHERE NOT EXISTS (
    SELECT 1 FROM public.presupuesto_detalle pd
    WHERE pd.idProyecto = p_idProyecto AND pd.partida = p_partida
  );

  -- total_gastado
  UPDATE public.presupuesto_detalle pd
  SET total_gastado = COALESCE((
      SELECT SUM(g.monto) FROM public.gastos_detalle g
      WHERE g.idProyecto = p_idProyecto AND g.partida = p_partida
  ), 0)
  WHERE pd.idProyecto = p_idProyecto AND pd.partida = p_partida;

  -- saldo_disponible = presupuesto - total_gastado (+/- recon si lo manejas aparte)
  UPDATE public.presupuesto_detalle pd
  SET saldo_disponible = COALESCE(presupuesto,0) - COALESCE(total_gastado,0) + COALESCE(total_reconducido,0)
  WHERE pd.idProyecto = p_idProyecto AND pd.partida = p_partida;
END;
$$;


--
-- Name: fn_saldo_disponible_partida(integer, integer, integer, integer, character varying, character varying, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_saldo_disponible_partida(p_dg integer, p_da integer, p_fuente integer, p_proyecto integer, p_clave character varying, p_mes character varying, p_ejercicio integer DEFAULT (EXTRACT(year FROM CURRENT_DATE))::integer) RETURNS TABLE(presupuesto_base numeric, reservado_suficiencias numeric, comprometido_vigente numeric, devengado_en_cerrados numeric, saldo_disponible numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY
  WITH
  -- Presupuesto base del mes para esa combinación de identificadores
  pbase AS (
    SELECT COALESCE(
      (SELECT CASE UPPER(p_mes)
         WHEN 'ENERO'      THEN pbp.ene
         WHEN 'FEBRERO'    THEN pbp.feb
         WHEN 'MARZO'      THEN pbp.mar
         WHEN 'ABRIL'      THEN pbp.abr
         WHEN 'MAYO'       THEN pbp.may
         WHEN 'JUNIO'      THEN pbp.jun
         WHEN 'JULIO'      THEN pbp.jul
         WHEN 'AGOSTO'     THEN pbp.ago
         WHEN 'SEPTIEMBRE' THEN pbp.sep
         WHEN 'OCTUBRE'    THEN pbp.oct
         WHEN 'NOVIEMBRE'  THEN pbp.nov
         WHEN 'DICIEMBRE'  THEN pbp.dic
         ELSE 0
       END
       FROM public.presupuesto_base_partidas pbp
       JOIN public.partidas pa ON pa.id = pbp.id_partida
       WHERE pbp.id_dgeneral  = p_dg
         AND pbp.id_dauxiliar = p_da
         AND pbp.id_fuente    = p_fuente
         AND pbp.id_proyecto  = p_proyecto
         AND pa.clave         = p_clave
         AND pbp.ejercicio    = p_ejercicio
       LIMIT 1
      ), 0) AS valor
  ),

  -- FASE 1: Suficiencias activas SIN comprometido asociado
  -- (el gasto está reservado pero aún no formalizado)
  suf_libre AS (
    SELECT COALESCE(SUM(sd.importe), 0) AS total
    FROM public.suficiencia_detalle sd
    JOIN public.suficiencias s ON s.id = sd.id_suficiencia
    LEFT JOIN public.comprometidos c ON c.id_suficiencia = s.id
    WHERE c.id IS NULL
      AND s.cancelled_at IS NULL
      AND s.id_dgeneral  = p_dg
      AND s.id_dauxiliar = p_da
      AND s.id_fuente    = p_fuente
      AND s.id_proyecto  = p_proyecto
      AND sd.clave       = p_clave
      AND UPPER(s.mes_pago)             = UPPER(p_mes)
      AND EXTRACT(YEAR FROM s.fecha)    = p_ejercicio
  ),

  -- FASE 2: Comprometidos VIGENTES (aún no cerrados ni cancelados)
  -- La suficiencia subyacente ya no cuenta; cuenta el comprometido
  comp_vigente AS (
    SELECT COALESCE(SUM(cd.importe), 0) AS total
    FROM public.comprometido_detalle cd
    JOIN public.comprometidos c ON c.id = cd.id_comprometido
    JOIN public.suficiencias s ON s.id = c.id_suficiencia
    WHERE UPPER(COALESCE(c.estatus, 'VIGENTE')) NOT IN ('CERRADO', 'CANCELADO')
      AND s.cancelled_at IS NULL
      AND s.id_dgeneral  = p_dg
      AND s.id_dauxiliar = p_da
      AND s.id_fuente    = p_fuente
      AND s.id_proyecto  = p_proyecto
      AND cd.clave       = p_clave
      AND UPPER(s.mes_pago)             = UPPER(p_mes)
      AND EXTRACT(YEAR FROM s.fecha)    = p_ejercicio
  ),

  -- FASE 3: Devengados de comprometidos ya CERRADOS
  -- El comprometido ya no cuenta; solo cuenta el gasto real devengado
  dev_en_cerrado AS (
    SELECT COALESCE(SUM(dd.importe), 0) AS total
    FROM public.devengado_detalle dd
    JOIN public.devengados d ON d.id = dd.id_devengado
    JOIN public.comprometidos c ON c.id = d.id_comprometido
    JOIN public.suficiencias s ON s.id = d.id_suficiencia
    WHERE UPPER(COALESCE(d.estatus, 'ACTIVO'))   != 'CANCELADO'
      AND UPPER(COALESCE(c.estatus, 'VIGENTE'))   = 'CERRADO'
      AND s.id_dgeneral  = p_dg
      AND s.id_dauxiliar = p_da
      AND s.id_fuente    = p_fuente
      AND s.id_proyecto  = p_proyecto
      AND dd.clave       = p_clave
      AND UPPER(s.mes_pago)             = UPPER(p_mes)
      AND EXTRACT(YEAR FROM s.fecha)    = p_ejercicio
  )

  SELECT
    pbase.valor                                                                           AS presupuesto_base,
    suf_libre.total                                                                       AS reservado_suficiencias,
    comp_vigente.total                                                                    AS comprometido_vigente,
    dev_en_cerrado.total                                                                  AS devengado_en_cerrados,
    pbase.valor - suf_libre.total - comp_vigente.total - dev_en_cerrado.total             AS saldo_disponible
  FROM pbase, suf_libre, comp_vigente, dev_en_cerrado;
END;
$$;


--
-- Name: FUNCTION fn_saldo_disponible_partida(p_dg integer, p_da integer, p_fuente integer, p_proyecto integer, p_clave character varying, p_mes character varying, p_ejercicio integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_saldo_disponible_partida(p_dg integer, p_da integer, p_fuente integer, p_proyecto integer, p_clave character varying, p_mes character varying, p_ejercicio integer) IS 'Calcula el saldo disponible de una partida por mes usando 3 fases para evitar doble conteo: (1) suficiencias sin comprometido, (2) comprometidos vigentes, (3) devengados de comprometidos cerrados.';


--
-- Name: fn_set_actualizado_en(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_set_actualizado_en() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.actualizado_en = now();
  RETURN NEW;
END;
$$;


--
-- Name: fn_set_no_suficiencia(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_set_no_suficiencia() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_year text;
  v_month text;
  v_seq text;
BEGIN
  -- Si no viene fecha, usa hoy
  IF NEW.fecha IS NULL THEN
    NEW.fecha := CURRENT_DATE;
  END IF;

  -- Si no viene folio_num, lo genera con el default/sequence
  IF NEW.folio_num IS NULL OR NEW.folio_num = 0 THEN
    NEW.folio_num := nextval('public.suficiencias_folio_num_seq');
  END IF;

  v_year  := to_char(NEW.fecha, 'YYYY');
  v_month := to_char(NEW.fecha, 'MM');
  v_seq   := lpad(NEW.folio_num::text, 4, '0');

  NEW.no_suficiencia := 'MUN-' || v_year || '-' || v_month || '-SP-' || v_seq;

  RETURN NEW;
END $$;


--
-- Name: fn_usuarios_audit(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_usuarios_audit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_actor_usuario text;
BEGIN
  -- intenta resolver el username del actor
  IF TG_OP IN ('INSERT','UPDATE') THEN
    IF NEW.updated_by IS NOT NULL THEN
      SELECT u.usuario INTO v_actor_usuario
      FROM public.usuarios u
      WHERE u.id = NEW.updated_by;
    END IF;
  ELSE
    IF OLD.updated_by IS NOT NULL THEN
      SELECT u.usuario INTO v_actor_usuario
      FROM public.usuarios u
      WHERE u.id = OLD.updated_by;
    END IF;
  END IF;

  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.usuarios_audit(usuario_id, accion, actor_id, actor_usuario, old_row, new_row)
    VALUES (NEW.id, 'INSERT', NEW.updated_by, v_actor_usuario, NULL, to_jsonb(NEW));
    RETURN NEW;

  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO public.usuarios_audit(usuario_id, accion, actor_id, actor_usuario, old_row, new_row)
    VALUES (NEW.id, 'UPDATE', NEW.updated_by, v_actor_usuario, to_jsonb(OLD), to_jsonb(NEW));
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO public.usuarios_audit(usuario_id, accion, actor_id, actor_usuario, old_row, new_row)
    VALUES (OLD.id, 'DELETE', OLD.updated_by, v_actor_usuario, to_jsonb(OLD), NULL);
    RETURN OLD;
  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: trg_gastos_detalle_aiud(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_gastos_detalle_aiud() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (TG_OP = 'INSERT') THEN
    PERFORM public.fn_recalcular_aggreg_presupuesto(NEW.idProyecto, NEW.partida);
    RETURN NEW;

  ELSIF (TG_OP = 'UPDATE') THEN
    IF (OLD.idProyecto <> NEW.idProyecto OR OLD.partida <> NEW.partida) THEN
      PERFORM public.fn_recalcular_aggreg_presupuesto(OLD.idProyecto, OLD.partida);
    END IF;
    PERFORM public.fn_recalcular_aggreg_presupuesto(NEW.idProyecto, NEW.partida);
    RETURN NEW;

  ELSIF (TG_OP = 'DELETE') THEN
    PERFORM public.fn_recalcular_aggreg_presupuesto(OLD.idProyecto, OLD.partida);
    RETURN OLD;
  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: trg_set_mes_pago_date(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_set_mes_pago_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.mes_pago IS NOT NULL AND NEW.mes_pago_date IS NULL THEN
      NEW.mes_pago_date := public.fn_mes_pago_to_date(NEW.mes_pago, COALESCE(NEW.fecha, NEW.created_at::date, current_date));
    END IF;
  ELSE
    IF NEW.mes_pago IS DISTINCT FROM OLD.mes_pago OR NEW.mes_pago_date IS NULL THEN
      IF NEW.mes_pago IS NOT NULL THEN
        NEW.mes_pago_date := public.fn_mes_pago_to_date(NEW.mes_pago, COALESCE(NEW.fecha, NEW.created_at::date, current_date));
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: trg_set_suf_expires_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_set_suf_expires_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.expires_at IS NULL THEN
    NEW.expires_at := public.fn_end_of_month_deadline(NEW.created_at);
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: trg_suficiencia_detalle_audit(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_suficiencia_detalle_audit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_actor integer;
  v_sufid integer;
BEGIN
  v_actor := NULLIF(current_setting('app.actor_id', true), '')::integer;

  IF TG_OP = 'INSERT' THEN
    v_sufid := NEW.id_suficiencia;
    INSERT INTO public.suficiencia_detalle_audit(accion, detalle_id, suficiencia_id, actor_id, old_row, new_row)
    VALUES ('INSERT', NEW.id, v_sufid, v_actor, NULL, to_jsonb(NEW));
    RETURN NEW;

  ELSIF TG_OP = 'UPDATE' THEN
    v_sufid := NEW.id_suficiencia;
    INSERT INTO public.suficiencia_detalle_audit(accion, detalle_id, suficiencia_id, actor_id, old_row, new_row)
    VALUES ('UPDATE', NEW.id, v_sufid, v_actor, to_jsonb(OLD), to_jsonb(NEW));
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    v_sufid := OLD.id_suficiencia;
    INSERT INTO public.suficiencia_detalle_audit(accion, detalle_id, suficiencia_id, actor_id, old_row, new_row)
    VALUES ('DELETE', OLD.id, v_sufid, v_actor, to_jsonb(OLD), NULL);
    RETURN OLD;
  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: trg_suficiencias_audit(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_suficiencias_audit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_actor integer;
BEGIN
  -- Si no existe la variable, regresa NULL (por eso el "true")
  v_actor := NULLIF(current_setting('app.actor_id', true), '')::integer;

  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.suficiencias_audit(accion, suficiencia_id, actor_id, old_row, new_row)
    VALUES ('INSERT', NEW.id, v_actor, NULL, to_jsonb(NEW));
    RETURN NEW;

  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO public.suficiencias_audit(accion, suficiencia_id, actor_id, old_row, new_row)
    VALUES ('UPDATE', NEW.id, v_actor, to_jsonb(OLD), to_jsonb(NEW));
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO public.suficiencias_audit(accion, suficiencia_id, actor_id, old_row, new_row)
    VALUES ('DELETE', OLD.id, v_actor, to_jsonb(OLD), NULL);
    RETURN OLD;
  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: update_actualizacion_timestamp(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_actualizacion_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.fecha_actualizacion = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: auditoria_accesos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditoria_accesos (
    id bigint NOT NULL,
    user_id bigint,
    dg_clave text,
    da_clave text,
    modulo text,
    recurso text,
    detalle text,
    permitido boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    actor_id integer,
    id_dgeneral integer,
    id_dauxiliar integer,
    metodo text,
    ruta text,
    motivo text,
    payload jsonb
);


--
-- Name: auditoria_accesos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auditoria_accesos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auditoria_accesos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auditoria_accesos_id_seq OWNED BY public.auditoria_accesos.id;


--
-- Name: auditoria_eventos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditoria_eventos (
    id bigint NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    tipo text NOT NULL,
    entidad text,
    entidad_id text,
    estado text,
    actor_id integer,
    id_dgeneral integer,
    id_dauxiliar integer,
    metodo text,
    ruta text,
    detalles jsonb
);


--
-- Name: auditoria_eventos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auditoria_eventos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auditoria_eventos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auditoria_eventos_id_seq OWNED BY public.auditoria_eventos.id;


--
-- Name: cat_impuesto_tipo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cat_impuesto_tipo (
    clave character varying(10) NOT NULL,
    descripcion text NOT NULL
);


--
-- Name: comprometido_detalle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comprometido_detalle (
    id integer NOT NULL,
    id_comprometido integer NOT NULL,
    renglon integer NOT NULL,
    clave character varying(50),
    concepto_partida character varying(350),
    justificacion text,
    descripcion text,
    importe numeric(18,2) DEFAULT 0,
    CONSTRAINT chk_comprometido_detalle_importe_nonneg CHECK ((importe >= (0)::numeric))
);


--
-- Name: comprometido_detalle_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.comprometido_detalle_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: comprometido_detalle_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.comprometido_detalle_id_seq OWNED BY public.comprometido_detalle.id;


--
-- Name: comprometidos_folio_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.comprometidos_folio_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: comprometidos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comprometidos (
    id integer NOT NULL,
    id_suficiencia integer NOT NULL,
    id_usuario integer NOT NULL,
    id_dgeneral integer NOT NULL,
    id_dauxiliar integer NOT NULL,
    id_proyecto integer NOT NULL,
    id_fuente integer NOT NULL,
    folio_num bigint DEFAULT nextval('public.comprometidos_folio_seq'::regclass) NOT NULL,
    no_comprometido character varying(50),
    fecha date,
    dependencia character varying(350),
    departamento character varying(350),
    fuente character varying(350),
    mes_pago character varying(12) NOT NULL,
    meta text,
    clave_programatica text,
    impuesto_tipo character varying(10) DEFAULT 'NONE'::character varying,
    isr_tasa numeric(5,2),
    ieps_tasa numeric(10,2),
    subtotal numeric(18,2),
    iva numeric(18,2),
    isr numeric(18,2),
    ieps numeric(18,2),
    total numeric(18,2) DEFAULT 0,
    cantidad_con_letra text,
    estatus character varying(30) DEFAULT 'VIGENTE'::character varying,
    fecha_cancelacion timestamp without time zone,
    motivo_cancelacion text,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    fecha_cierre timestamp without time zone,
    monto_liberado numeric(14,2) DEFAULT 0 NOT NULL,
    mes_pago_date date,
    firma_enlace_label character varying(200),
    firma_enlace_nombre character varying(200),
    firma_area_label character varying(200),
    firma_area_nombre character varying(200),
    firma_direccion_nombre character varying(200),
    CONSTRAINT chk_comprometidos_ieps_nonneg CHECK ((ieps >= (0)::numeric)),
    CONSTRAINT chk_comprometidos_isr_nonneg CHECK ((isr >= (0)::numeric)),
    CONSTRAINT chk_comprometidos_iva_nonneg CHECK ((iva >= (0)::numeric)),
    CONSTRAINT chk_comprometidos_monto_liberado_nonneg CHECK ((monto_liberado >= (0)::numeric)),
    CONSTRAINT chk_comprometidos_subtotal_nonneg CHECK ((subtotal >= (0)::numeric)),
    CONSTRAINT chk_comprometidos_total_nonneg CHECK ((total >= (0)::numeric))
);


--
-- Name: TABLE comprometidos; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.comprometidos IS 'Gastos comprometidos derivados de una suficiencia. estatus: VIGENTE | CERRADO | CANCELADO.';


--
-- Name: comprometidos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.comprometidos_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: comprometidos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.comprometidos_id_seq OWNED BY public.comprometidos.id;


--
-- Name: dauxiliar; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dauxiliar (
    id integer NOT NULL,
    clave character varying(20) NOT NULL,
    dependencia character varying(350) NOT NULL
);


--
-- Name: dauxiliar_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dauxiliar_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dauxiliar_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dauxiliar_id_seq OWNED BY public.dauxiliar.id;


--
-- Name: devengado_detalle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.devengado_detalle (
    id integer NOT NULL,
    id_devengado integer NOT NULL,
    renglon integer NOT NULL,
    clave character varying(50),
    concepto_partida character varying(350),
    justificacion text,
    descripcion text,
    importe numeric(18,2) DEFAULT 0,
    CONSTRAINT chk_devengado_detalle_importe_nonneg CHECK ((importe >= (0)::numeric))
);


--
-- Name: devengado_detalle_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.devengado_detalle_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: devengado_detalle_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.devengado_detalle_id_seq OWNED BY public.devengado_detalle.id;


--
-- Name: devengados_folio_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.devengados_folio_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: devengados; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.devengados (
    id integer NOT NULL,
    id_comprometido integer NOT NULL,
    id_suficiencia integer NOT NULL,
    id_usuario integer NOT NULL,
    id_dgeneral integer NOT NULL,
    id_dauxiliar integer NOT NULL,
    id_proyecto integer NOT NULL,
    id_fuente integer NOT NULL,
    folio_num bigint DEFAULT nextval('public.devengados_folio_seq'::regclass) NOT NULL,
    no_devengado character varying(50),
    fecha date,
    dependencia character varying(350),
    departamento character varying(350),
    fuente character varying(350),
    mes_pago character varying(12) NOT NULL,
    meta text,
    clave_programatica text,
    impuesto_tipo character varying(10) DEFAULT 'NONE'::character varying,
    isr_tasa numeric(5,2),
    ieps_tasa numeric(10,2),
    subtotal numeric(18,2),
    iva numeric(18,2),
    isr numeric(18,2),
    ieps numeric(18,2),
    total numeric(18,2) DEFAULT 0,
    cantidad_con_letra text,
    estatus character varying(30) DEFAULT 'VIGENTE'::character varying,
    fecha_cancelacion timestamp without time zone,
    motivo_cancelacion text,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    mes_pago_date date,
    firma_enlace_label character varying(200),
    firma_enlace_nombre character varying(200),
    firma_area_label character varying(200),
    firma_area_nombre character varying(200),
    firma_direccion_nombre character varying(200),
    CONSTRAINT chk_devengados_ieps_nonneg CHECK ((ieps >= (0)::numeric)),
    CONSTRAINT chk_devengados_isr_nonneg CHECK ((isr >= (0)::numeric)),
    CONSTRAINT chk_devengados_iva_nonneg CHECK ((iva >= (0)::numeric)),
    CONSTRAINT chk_devengados_subtotal_nonneg CHECK ((subtotal >= (0)::numeric)),
    CONSTRAINT chk_devengados_total_nonneg CHECK ((total >= (0)::numeric))
);


--
-- Name: TABLE devengados; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.devengados IS 'Gastos devengados (ejercidos reales). El monto devengado puede ser menor al comprometido; la diferencia queda liberada.';


--
-- Name: devengados_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.devengados_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: devengados_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.devengados_id_seq OWNED BY public.devengados.id;


--
-- Name: dgeneral; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dgeneral (
    id integer NOT NULL,
    clave character varying(20) NOT NULL,
    dependencia character varying(350) NOT NULL
);


--
-- Name: dgeneral_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dgeneral_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dgeneral_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dgeneral_id_seq OWNED BY public.dgeneral.id;


--
-- Name: expedientes_entrega; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.expedientes_entrega (
    id bigint NOT NULL,
    anio integer NOT NULL,
    mes smallint NOT NULL,
    id_suficiencia bigint,
    id_comprometido bigint,
    id_devengado bigint,
    id_dgeneral integer,
    id_dauxiliar integer,
    partida_clave character varying(20),
    folio character varying(60) NOT NULL,
    dependencia character varying(350) NOT NULL,
    concepto text NOT NULL,
    importe numeric(18,2) DEFAULT 0 NOT NULL,
    entrego_comprometido boolean DEFAULT false NOT NULL,
    entrego_devengado boolean DEFAULT false NOT NULL,
    fecha_entrega_tesoreria date,
    fecha_recibido_presupuesto date,
    estatus public.entrega_estatus DEFAULT 'ENTREGADO'::public.entrega_estatus NOT NULL,
    observaciones text,
    creado_por integer,
    creado_en timestamp without time zone DEFAULT now() NOT NULL,
    actualizado_en timestamp without time zone DEFAULT now() NOT NULL,
    column23 integer,
    CONSTRAINT expedientes_entrega_mes_check CHECK (((mes >= 1) AND (mes <= 12)))
);


--
-- Name: expedientes_entrega_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.expedientes_entrega_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: expedientes_entrega_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.expedientes_entrega_id_seq OWNED BY public.expedientes_entrega.id;


--
-- Name: fuentes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fuentes (
    id integer NOT NULL,
    clave character varying(20) NOT NULL,
    fuente character varying(350) NOT NULL
);


--
-- Name: fuentes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.fuentes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: fuentes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.fuentes_id_seq OWNED BY public.fuentes.id;


--
-- Name: gastos_detalle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gastos_detalle (
    id integer NOT NULL,
    id_dgeneral integer NOT NULL,
    id_dauxiliar integer NOT NULL,
    id_fuente integer NOT NULL,
    id_proyecto text NOT NULL,
    partida character varying(20) NOT NULL,
    fecha date,
    descripcion text,
    monto numeric(18,2) NOT NULL
);


--
-- Name: gastos_detalle_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.gastos_detalle_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gastos_detalle_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.gastos_detalle_id_seq OWNED BY public.gastos_detalle.id;


--
-- Name: metas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metas (
    id integer NOT NULL,
    dg_clave character varying(5) NOT NULL,
    da_clave character varying(5) NOT NULL,
    proy_clave character varying(15) NOT NULL,
    conac character(1) NOT NULL,
    meta text NOT NULL,
    activo boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now(),
    ext_id character varying(50)
);


--
-- Name: metas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metas_id_seq OWNED BY public.metas.id;


--
-- Name: partidas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.partidas (
    id integer NOT NULL,
    clave character varying(20) NOT NULL,
    descripcion character varying(250) NOT NULL
);


--
-- Name: partidas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.partidas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: partidas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.partidas_id_seq OWNED BY public.partidas.id;


--
-- Name: partidas_permitidas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.partidas_permitidas (
    id integer NOT NULL,
    dgeneral_clave character varying(10) NOT NULL,
    dauxiliar_clave character varying(10) NOT NULL,
    proyecto_clave character varying(20) NOT NULL,
    fuente_clave character varying(20) NOT NULL,
    partida_clave character varying(20) NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE partidas_permitidas; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.partidas_permitidas IS 'Catálogo de combinaciones DG/DA/proyecto/fuente/partida permitidas por dependencia. Poblado por seedPartidasPermitidas() al iniciar el servidor.';


--
-- Name: partidas_permitidas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.partidas_permitidas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: partidas_permitidas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.partidas_permitidas_id_seq OWNED BY public.partidas_permitidas.id;


--
-- Name: partidas_presupuesto; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.partidas_presupuesto (
    id integer NOT NULL,
    id_usuario integer NOT NULL,
    partida_clave character varying(20) NOT NULL,
    monto numeric(18,2) DEFAULT 0 NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL,
    ejercicio integer DEFAULT EXTRACT(year FROM now()) NOT NULL
);


--
-- Name: partidas_presupuesto_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.partidas_presupuesto_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: partidas_presupuesto_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.partidas_presupuesto_id_seq OWNED BY public.partidas_presupuesto.id;


--
-- Name: presupuesto_base_partidas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.presupuesto_base_partidas (
    id bigint NOT NULL,
    id_dgeneral integer NOT NULL,
    id_dauxiliar integer NOT NULL,
    id_fuente integer NOT NULL,
    id_partida integer NOT NULL,
    id_proyecto integer,
    ejercicio integer NOT NULL,
    ene numeric(18,2) DEFAULT 0 NOT NULL,
    feb numeric(18,2) DEFAULT 0 NOT NULL,
    mar numeric(18,2) DEFAULT 0 NOT NULL,
    abr numeric(18,2) DEFAULT 0 NOT NULL,
    may numeric(18,2) DEFAULT 0 NOT NULL,
    jun numeric(18,2) DEFAULT 0 NOT NULL,
    jul numeric(18,2) DEFAULT 0 NOT NULL,
    ago numeric(18,2) DEFAULT 0 NOT NULL,
    sep numeric(18,2) DEFAULT 0 NOT NULL,
    oct numeric(18,2) DEFAULT 0 NOT NULL,
    nov numeric(18,2) DEFAULT 0 NOT NULL,
    dic numeric(18,2) DEFAULT 0 NOT NULL,
    total numeric(18,2) GENERATED ALWAYS AS ((((((((((((COALESCE(ene, (0)::numeric) + COALESCE(feb, (0)::numeric)) + COALESCE(mar, (0)::numeric)) + COALESCE(abr, (0)::numeric)) + COALESCE(may, (0)::numeric)) + COALESCE(jun, (0)::numeric)) + COALESCE(jul, (0)::numeric)) + COALESCE(ago, (0)::numeric)) + COALESCE(sep, (0)::numeric)) + COALESCE(oct, (0)::numeric)) + COALESCE(nov, (0)::numeric)) + COALESCE(dic, (0)::numeric))) STORED,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE presupuesto_base_partidas; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.presupuesto_base_partidas IS 'Presupuesto mensual original cargado por partida/DG/DA/fuente/proyecto. Las columnas ene..dic representan el presupuesto asignado por mes. NO se modifica por movimientos; el saldo disponible se calcula mediante fn_saldo_disponible_partida.';


--
-- Name: presupuesto_base_partidas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.presupuesto_base_partidas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: presupuesto_base_partidas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.presupuesto_base_partidas_id_seq OWNED BY public.presupuesto_base_partidas.id;


--
-- Name: presupuesto_detalle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.presupuesto_detalle (
    id integer NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now(),
    id_dgeneral integer,
    id_dauxiliar integer,
    id_fuente integer,
    id_proyecto text,
    partida character varying(20) NOT NULL,
    presupuesto numeric(18,2) DEFAULT 0,
    total_gastado numeric(18,2) DEFAULT 0,
    total_reconducido numeric(18,2) DEFAULT 0,
    saldo_disponible numeric(18,2) DEFAULT 0,
    fecha_cuando_se_gasto date,
    en_que_se_gasto text,
    fecha_reconduccion date,
    motivo_reconduccion text,
    mes character varying(7) NOT NULL
);


--
-- Name: presupuesto_detalle_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.presupuesto_detalle_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: presupuesto_detalle_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.presupuesto_detalle_id_seq OWNED BY public.presupuesto_detalle.id;


--
-- Name: programas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.programas (
    id integer NOT NULL,
    clave character varying(20),
    descripcion character varying(250)
);


--
-- Name: programas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.programas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: programas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.programas_id_seq OWNED BY public.programas.id;


--
-- Name: proyectos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.proyectos (
    id integer NOT NULL,
    clave character varying(20) NOT NULL,
    descripcion text NOT NULL,
    conac character varying(5)
);


--
-- Name: proyectos_fuentes_permitidas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.proyectos_fuentes_permitidas (
    id integer NOT NULL,
    dgeneral_clave character varying(10) NOT NULL,
    dauxiliar_clave character varying(10) NOT NULL,
    proyecto_clave character varying(10) NOT NULL,
    fuente_clave character varying(10) NOT NULL,
    dgeneral_id integer
);


--
-- Name: proyectos_fuentes_permitidas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.proyectos_fuentes_permitidas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: proyectos_fuentes_permitidas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.proyectos_fuentes_permitidas_id_seq OWNED BY public.proyectos_fuentes_permitidas.id;


--
-- Name: proyectos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.proyectos_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: proyectos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.proyectos_id_seq OWNED BY public.proyectos.id;


--
-- Name: reconduccion_oficios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reconduccion_oficios (
    id integer NOT NULL,
    id_reconduccion bigint NOT NULL,
    nombre_archivo character varying(255) NOT NULL,
    ruta_archivo character varying(500) NOT NULL,
    tamano_bytes integer,
    subido_por integer,
    fecha_subida timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: reconduccion_oficios_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reconduccion_oficios_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reconduccion_oficios_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reconduccion_oficios_id_seq OWNED BY public.reconduccion_oficios.id;


--
-- Name: reconducciones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reconducciones (
    id bigint NOT NULL,
    oficio character varying(50),
    fecha_elaboracion date,
    tipo_movimiento character varying(20) DEFAULT 'RECONDUCCION'::character varying NOT NULL,
    justificacion text,
    estatus character varying(20) DEFAULT 'BORRADOR'::character varying NOT NULL,
    ejercicio integer,
    mes_pago_date date,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    created_by integer,
    updated_at timestamp without time zone,
    updated_by integer,
    enviado_at timestamp without time zone,
    autorizado_at timestamp without time zone,
    aplicado_at timestamp without time zone,
    cancel_at timestamp without time zone,
    cancel_by integer,
    cancel_reason text,
    firma_enlace_label character varying(200),
    firma_enlace_nombre character varying(200),
    firma_area_label character varying(200),
    firma_area_nombre character varying(200),
    firma_direccion_nombre character varying(200),
    CONSTRAINT chk_reconducciones_estatus CHECK (((estatus)::text = ANY (ARRAY[('BORRADOR'::character varying)::text, ('ENVIADO'::character varying)::text, ('AUTORIZADO'::character varying)::text, ('APLICADO'::character varying)::text, ('CANCELADO'::character varying)::text]))),
    CONSTRAINT chk_reconducciones_tipo CHECK (((tipo_movimiento)::text = ANY (ARRAY[('TRASPASO'::character varying)::text, ('RECONDUCCION'::character varying)::text, ('AMPLIACION'::character varying)::text, ('REDUCCION'::character varying)::text])))
);


--
-- Name: TABLE reconducciones; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.reconducciones IS 'Documentos de reconducción presupuestal. estatus: BORRADOR | ENVIADO | AUTORIZADO | APLICADO | CANCELADO.';


--
-- Name: reconducciones_claves; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reconducciones_claves (
    id integer NOT NULL,
    clave character varying(6) NOT NULL,
    dg_clave character varying(3) NOT NULL,
    da_clave character varying(3) NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    created_by integer,
    status character varying(10) DEFAULT 'ACTIVA'::character varying NOT NULL,
    used_at timestamp without time zone,
    used_by integer
);


--
-- Name: reconducciones_claves_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reconducciones_claves_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reconducciones_claves_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reconducciones_claves_id_seq OWNED BY public.reconducciones_claves.id;


--
-- Name: reconducciones_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reconducciones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reconducciones_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reconducciones_id_seq OWNED BY public.reconducciones.id;


--
-- Name: reconducciones_lados; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reconducciones_lados (
    id bigint NOT NULL,
    id_reconduccion bigint NOT NULL,
    lado character varying(10) NOT NULL,
    id_dgeneral integer,
    id_dauxiliar integer,
    id_programa integer,
    objetivo text,
    id_fuente integer,
    id_proyecto integer,
    clave_proyecto character varying(50),
    denominacion text,
    CONSTRAINT chk_reconducciones_lados_lado CHECK (((lado)::text = ANY (ARRAY[('ORIGEN'::character varying)::text, ('DESTINO'::character varying)::text])))
);


--
-- Name: reconducciones_lados_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reconducciones_lados_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reconducciones_lados_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reconducciones_lados_id_seq OWNED BY public.reconducciones_lados.id;


--
-- Name: reconducciones_metas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reconducciones_metas (
    id bigint NOT NULL,
    id_reconduccion bigint NOT NULL,
    lado character varying(10) NOT NULL,
    codigo character varying(50),
    descripcion text,
    unidad_medida character varying(50),
    inicial numeric(14,2),
    avance numeric(14,2),
    modificada numeric(14,2),
    t1 numeric(14,2),
    t2 numeric(14,2),
    t3 numeric(14,2),
    t4 numeric(14,2),
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    created_by integer,
    CONSTRAINT chk_reconducciones_metas_lado CHECK (((lado)::text = ANY (ARRAY[('ORIGEN'::character varying)::text, ('DESTINO'::character varying)::text])))
);


--
-- Name: reconducciones_metas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reconducciones_metas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reconducciones_metas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reconducciones_metas_id_seq OWNED BY public.reconducciones_metas.id;


--
-- Name: reconducciones_movimientos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reconducciones_movimientos (
    id bigint NOT NULL,
    id_reconduccion bigint NOT NULL,
    lado character varying(10) NOT NULL,
    id_dgeneral integer,
    id_dauxiliar integer,
    id_fuente integer,
    id_proyecto integer,
    id_partida integer NOT NULL,
    ejercicio integer,
    mes_pago_date date,
    monto numeric(14,2) NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    created_by integer,
    CONSTRAINT chk_reconducciones_mov_lado CHECK (((lado)::text = ANY (ARRAY[('ORIGEN'::character varying)::text, ('DESTINO'::character varying)::text]))),
    CONSTRAINT chk_reconducciones_mov_signo CHECK (((((lado)::text = 'ORIGEN'::text) AND (monto < (0)::numeric)) OR (((lado)::text = 'DESTINO'::text) AND (monto > (0)::numeric))))
);


--
-- Name: reconducciones_movimientos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reconducciones_movimientos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reconducciones_movimientos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reconducciones_movimientos_id_seq OWNED BY public.reconducciones_movimientos.id;


--
-- Name: reconducciones_recursos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reconducciones_recursos (
    id bigint NOT NULL,
    id_reconduccion bigint NOT NULL,
    lado character varying(10) NOT NULL,
    id_partida integer NOT NULL,
    concepto_partida text,
    autorizado numeric(14,2),
    por_ejercer numeric(14,2),
    monto_movimiento numeric(14,2) DEFAULT 0 NOT NULL,
    autorizado_modificado numeric(14,2),
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    created_by integer,
    CONSTRAINT chk_reconducciones_recursos_lado CHECK (((lado)::text = ANY (ARRAY[('ORIGEN'::character varying)::text, ('DESTINO'::character varying)::text]))),
    CONSTRAINT chk_reconducciones_recursos_monto CHECK ((monto_movimiento >= (0)::numeric))
);


--
-- Name: reconducciones_recursos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reconducciones_recursos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reconducciones_recursos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reconducciones_recursos_id_seq OWNED BY public.reconducciones_recursos.id;


--
-- Name: reconducciones_sesiones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reconducciones_sesiones (
    token character varying(64) NOT NULL,
    id_dgeneral integer NOT NULL,
    id_dauxiliar integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    created_by integer,
    activo boolean DEFAULT true NOT NULL
);


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    id integer NOT NULL,
    clave character varying(20) NOT NULL,
    descripcion character varying(100) NOT NULL
);


--
-- Name: roles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.roles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.roles_id_seq OWNED BY public.roles.id;


--
-- Name: seq_comprometido_folio; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.seq_comprometido_folio
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: seq_devengado_folio; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.seq_devengado_folio
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: seq_reconduccion_folio; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.seq_reconduccion_folio
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: seq_suficiencia_folio; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.seq_suficiencia_folio
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: suficiencia_detalle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.suficiencia_detalle (
    id integer NOT NULL,
    id_suficiencia integer NOT NULL,
    renglon integer NOT NULL,
    clave character varying(50),
    concepto_partida character varying(350),
    justificacion text,
    descripcion text,
    importe numeric(18,2) DEFAULT 0
);


--
-- Name: TABLE suficiencia_detalle; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.suficiencia_detalle IS 'Renglones de partida por suficiencia. La clave referencia partidas.clave (texto, no FK para permitir flexibilidad histórica).';


--
-- Name: suficiencia_detalle_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.suficiencia_detalle_audit (
    audit_id bigint NOT NULL,
    accion text NOT NULL,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    detalle_id integer,
    suficiencia_id integer,
    actor_id integer,
    old_row jsonb,
    new_row jsonb
);


--
-- Name: suficiencia_detalle_audit_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.suficiencia_detalle_audit_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: suficiencia_detalle_audit_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.suficiencia_detalle_audit_audit_id_seq OWNED BY public.suficiencia_detalle_audit.audit_id;


--
-- Name: suficiencia_detalle_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.suficiencia_detalle_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: suficiencia_detalle_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.suficiencia_detalle_id_seq OWNED BY public.suficiencia_detalle.id;


--
-- Name: suficiencias_folio_num_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.suficiencias_folio_num_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: suficiencias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.suficiencias (
    id integer NOT NULL,
    id_usuario integer NOT NULL,
    id_dgeneral integer NOT NULL,
    no_suficiencia character varying(50),
    fecha date,
    dependencia character varying(350),
    departamento character varying(350),
    fuente character varying(350),
    partida character varying(20),
    mes_pago character varying(12) NOT NULL,
    meta text,
    total numeric(18,2) DEFAULT 0,
    cantidad_con_letra text,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    folio_num bigint DEFAULT nextval('public.suficiencias_folio_num_seq'::regclass) NOT NULL,
    id_dauxiliar integer NOT NULL,
    id_proyecto integer NOT NULL,
    id_fuente integer NOT NULL,
    clave_programatica text,
    impuesto_tipo character varying(10) DEFAULT 'NONE'::character varying,
    isr_tasa numeric(5,2),
    subtotal numeric(18,2),
    iva numeric(18,2),
    isr numeric(18,2),
    ieps_tasa numeric(10,2),
    ieps numeric(14,2),
    pension_total numeric(18,2) DEFAULT 0,
    pension1_tasa numeric(5,2),
    pension1 numeric(18,2) DEFAULT 0,
    pension2_tasa numeric(5,2),
    pension2 numeric(18,2) DEFAULT 0,
    pension3_tasa numeric(5,2),
    pension3 numeric(18,2) DEFAULT 0,
    pension4_tasa numeric(5,2),
    pension4 numeric(18,2) DEFAULT 0,
    pension5_tasa numeric(5,2),
    pension5 numeric(18,2) DEFAULT 0,
    cancelled_at timestamp without time zone,
    cancelled_by integer,
    cancel_reason text,
    expires_at timestamp without time zone,
    mes_pago_date date,
    firma_enlace_label character varying(200),
    firma_enlace_nombre character varying(200),
    firma_area_label character varying(200),
    firma_area_nombre character varying(200),
    firma_direccion_nombre character varying(200)
);


--
-- Name: TABLE suficiencias; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.suficiencias IS 'Documentos de Suficiencia Presupuestal. El campo mes_pago indica el mes al que se carga el gasto. Flujo: suficiencias → comprometidos → devengados.';


--
-- Name: suficiencias_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.suficiencias_audit (
    audit_id bigint NOT NULL,
    accion text NOT NULL,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    suficiencia_id integer,
    actor_id integer,
    old_row jsonb,
    new_row jsonb
);


--
-- Name: suficiencias_audit_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.suficiencias_audit_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: suficiencias_audit_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.suficiencias_audit_audit_id_seq OWNED BY public.suficiencias_audit.audit_id;


--
-- Name: suficiencias_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.suficiencias_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: suficiencias_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.suficiencias_id_seq OWNED BY public.suficiencias.id;


--
-- Name: usuario_rol; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuario_rol (
    id_usuario integer NOT NULL,
    id_rol integer NOT NULL
);


--
-- Name: usuarios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuarios (
    id integer NOT NULL,
    nombre_completo character varying(200) NOT NULL,
    usuario character varying(50) NOT NULL,
    correo character varying(150),
    password character varying(200) NOT NULL,
    id_dgeneral integer,
    activo boolean DEFAULT true NOT NULL,
    fecha_creacion timestamp without time zone DEFAULT now() NOT NULL,
    ultimo_acceso timestamp without time zone,
    id_dauxiliar integer,
    updated_at timestamp without time zone,
    updated_by integer
);


--
-- Name: usuarios_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuarios_audit (
    audit_id bigint NOT NULL,
    usuario_id integer NOT NULL,
    accion text NOT NULL,
    actor_id integer,
    actor_usuario text,
    fecha timestamp without time zone DEFAULT now() NOT NULL,
    old_row jsonb,
    new_row jsonb,
    CONSTRAINT usuarios_audit_accion_check CHECK ((accion = ANY (ARRAY['INSERT'::text, 'UPDATE'::text, 'DELETE'::text])))
);


--
-- Name: usuarios_audit_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.usuarios_audit_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: usuarios_audit_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.usuarios_audit_audit_id_seq OWNED BY public.usuarios_audit.audit_id;


--
-- Name: usuarios_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.usuarios_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: usuarios_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.usuarios_id_seq OWNED BY public.usuarios.id;


--
-- Name: v_reconducciones_resumen; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_reconducciones_resumen AS
 SELECT r.id AS id_reconduccion,
    r.id,
    r.oficio AS no_oficio,
    r.fecha_elaboracion,
    r.tipo_movimiento,
    r.estatus,
    r.created_at,
    COALESCE(sum(
        CASE
            WHEN ((rr.lado)::text = 'ORIGEN'::text) THEN rr.monto_movimiento
            ELSE NULL::numeric
        END), (0)::numeric) AS total_origen,
    COALESCE(sum(
        CASE
            WHEN ((rr.lado)::text = 'DESTINO'::text) THEN rr.monto_movimiento
            ELSE NULL::numeric
        END), (0)::numeric) AS total_destino,
    COALESCE(sum(
        CASE
            WHEN ((rr.lado)::text = 'ORIGEN'::text) THEN rr.monto_movimiento
            ELSE NULL::numeric
        END), (0)::numeric) AS origen_total,
    COALESCE(sum(
        CASE
            WHEN ((rr.lado)::text = 'DESTINO'::text) THEN rr.monto_movimiento
            ELSE NULL::numeric
        END), (0)::numeric) AS destino_total,
    (COALESCE(sum(
        CASE
            WHEN ((rr.lado)::text = 'DESTINO'::text) THEN rr.monto_movimiento
            ELSE NULL::numeric
        END), (0)::numeric) - COALESCE(sum(
        CASE
            WHEN ((rr.lado)::text = 'ORIGEN'::text) THEN rr.monto_movimiento
            ELSE NULL::numeric
        END), (0)::numeric)) AS diferencia
   FROM (public.reconducciones r
     LEFT JOIN public.reconducciones_recursos rr ON ((rr.id_reconduccion = r.id)))
  GROUP BY r.id, r.oficio, r.fecha_elaboracion, r.tipo_movimiento, r.estatus, r.created_at;


--
-- Name: v_suficiencias_estado; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_suficiencias_estado AS
 SELECT id,
    id_usuario,
    id_dgeneral,
    no_suficiencia,
    fecha,
    dependencia,
    departamento,
    fuente,
    partida,
    mes_pago,
    meta,
    total,
    cantidad_con_letra,
    created_at,
    folio_num,
    id_dauxiliar,
    id_proyecto,
    id_fuente,
    clave_programatica,
    impuesto_tipo,
    isr_tasa,
    subtotal,
    iva,
    isr,
    ieps_tasa,
    ieps,
    pension_total,
    pension1_tasa,
    pension1,
    pension2_tasa,
    pension2,
    pension3_tasa,
    pension3,
    pension4_tasa,
    pension4,
    pension5_tasa,
    pension5,
    cancelled_at,
    cancelled_by,
    cancel_reason,
    expires_at,
        CASE
            WHEN (cancelled_at IS NOT NULL) THEN 'CANCELADO'::text
            WHEN (now() > expires_at) THEN 'CADUCADO'::text
            ELSE 'ACTIVO'::text
        END AS estado,
        CASE
            WHEN (cancelled_at IS NOT NULL) THEN NULL::interval
            WHEN (now() > expires_at) THEN '00:00:00'::interval
            ELSE ((expires_at)::timestamp with time zone - now())
        END AS tiempo_restante,
        CASE
            WHEN ((cancelled_at IS NOT NULL) OR (now() > expires_at)) THEN 0
            ELSE (floor((EXTRACT(epoch FROM ((expires_at)::timestamp with time zone - now())) / (86400)::numeric)))::integer
        END AS dias_restantes,
        CASE
            WHEN ((cancelled_at IS NOT NULL) OR (now() > expires_at)) THEN 0
            ELSE (floor((mod(EXTRACT(epoch FROM ((expires_at)::timestamp with time zone - now())), (86400)::numeric) / (3600)::numeric)))::integer
        END AS horas_restantes
   FROM public.suficiencias s;


--
-- Name: auditoria_accesos id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria_accesos ALTER COLUMN id SET DEFAULT nextval('public.auditoria_accesos_id_seq'::regclass);


--
-- Name: auditoria_eventos id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria_eventos ALTER COLUMN id SET DEFAULT nextval('public.auditoria_eventos_id_seq'::regclass);


--
-- Name: comprometido_detalle id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comprometido_detalle ALTER COLUMN id SET DEFAULT nextval('public.comprometido_detalle_id_seq'::regclass);


--
-- Name: comprometidos id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comprometidos ALTER COLUMN id SET DEFAULT nextval('public.comprometidos_id_seq'::regclass);


--
-- Name: dauxiliar id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dauxiliar ALTER COLUMN id SET DEFAULT nextval('public.dauxiliar_id_seq'::regclass);


--
-- Name: devengado_detalle id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devengado_detalle ALTER COLUMN id SET DEFAULT nextval('public.devengado_detalle_id_seq'::regclass);


--
-- Name: devengados id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devengados ALTER COLUMN id SET DEFAULT nextval('public.devengados_id_seq'::regclass);


--
-- Name: dgeneral id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dgeneral ALTER COLUMN id SET DEFAULT nextval('public.dgeneral_id_seq'::regclass);


--
-- Name: expedientes_entrega id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expedientes_entrega ALTER COLUMN id SET DEFAULT nextval('public.expedientes_entrega_id_seq'::regclass);


--
-- Name: fuentes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fuentes ALTER COLUMN id SET DEFAULT nextval('public.fuentes_id_seq'::regclass);


--
-- Name: gastos_detalle id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gastos_detalle ALTER COLUMN id SET DEFAULT nextval('public.gastos_detalle_id_seq'::regclass);


--
-- Name: metas id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metas ALTER COLUMN id SET DEFAULT nextval('public.metas_id_seq'::regclass);


--
-- Name: partidas id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partidas ALTER COLUMN id SET DEFAULT nextval('public.partidas_id_seq'::regclass);


--
-- Name: partidas_permitidas id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partidas_permitidas ALTER COLUMN id SET DEFAULT nextval('public.partidas_permitidas_id_seq'::regclass);


--
-- Name: partidas_presupuesto id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partidas_presupuesto ALTER COLUMN id SET DEFAULT nextval('public.partidas_presupuesto_id_seq'::regclass);


--
-- Name: presupuesto_base_partidas id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presupuesto_base_partidas ALTER COLUMN id SET DEFAULT nextval('public.presupuesto_base_partidas_id_seq'::regclass);


--
-- Name: presupuesto_detalle id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presupuesto_detalle ALTER COLUMN id SET DEFAULT nextval('public.presupuesto_detalle_id_seq'::regclass);


--
-- Name: programas id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.programas ALTER COLUMN id SET DEFAULT nextval('public.programas_id_seq'::regclass);


--
-- Name: proyectos id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proyectos ALTER COLUMN id SET DEFAULT nextval('public.proyectos_id_seq'::regclass);


--
-- Name: proyectos_fuentes_permitidas id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proyectos_fuentes_permitidas ALTER COLUMN id SET DEFAULT nextval('public.proyectos_fuentes_permitidas_id_seq'::regclass);


--
-- Name: reconduccion_oficios id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconduccion_oficios ALTER COLUMN id SET DEFAULT nextval('public.reconduccion_oficios_id_seq'::regclass);


--
-- Name: reconducciones id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones ALTER COLUMN id SET DEFAULT nextval('public.reconducciones_id_seq'::regclass);


--
-- Name: reconducciones_claves id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_claves ALTER COLUMN id SET DEFAULT nextval('public.reconducciones_claves_id_seq'::regclass);


--
-- Name: reconducciones_lados id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_lados ALTER COLUMN id SET DEFAULT nextval('public.reconducciones_lados_id_seq'::regclass);


--
-- Name: reconducciones_metas id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_metas ALTER COLUMN id SET DEFAULT nextval('public.reconducciones_metas_id_seq'::regclass);


--
-- Name: reconducciones_movimientos id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_movimientos ALTER COLUMN id SET DEFAULT nextval('public.reconducciones_movimientos_id_seq'::regclass);


--
-- Name: reconducciones_recursos id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_recursos ALTER COLUMN id SET DEFAULT nextval('public.reconducciones_recursos_id_seq'::regclass);


--
-- Name: roles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles ALTER COLUMN id SET DEFAULT nextval('public.roles_id_seq'::regclass);


--
-- Name: suficiencia_detalle id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suficiencia_detalle ALTER COLUMN id SET DEFAULT nextval('public.suficiencia_detalle_id_seq'::regclass);


--
-- Name: suficiencia_detalle_audit audit_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suficiencia_detalle_audit ALTER COLUMN audit_id SET DEFAULT nextval('public.suficiencia_detalle_audit_audit_id_seq'::regclass);


--
-- Name: suficiencias id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suficiencias ALTER COLUMN id SET DEFAULT nextval('public.suficiencias_id_seq'::regclass);


--
-- Name: suficiencias_audit audit_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suficiencias_audit ALTER COLUMN audit_id SET DEFAULT nextval('public.suficiencias_audit_audit_id_seq'::regclass);


--
-- Name: usuarios id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios ALTER COLUMN id SET DEFAULT nextval('public.usuarios_id_seq'::regclass);


--
-- Name: usuarios_audit audit_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios_audit ALTER COLUMN audit_id SET DEFAULT nextval('public.usuarios_audit_audit_id_seq'::regclass);


--
-- Name: auditoria_accesos auditoria_accesos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria_accesos
    ADD CONSTRAINT auditoria_accesos_pkey PRIMARY KEY (id);


--
-- Name: auditoria_eventos auditoria_eventos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria_eventos
    ADD CONSTRAINT auditoria_eventos_pkey PRIMARY KEY (id);


--
-- Name: cat_impuesto_tipo cat_impuesto_tipo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cat_impuesto_tipo
    ADD CONSTRAINT cat_impuesto_tipo_pkey PRIMARY KEY (clave);


--
-- Name: comprometido_detalle comprometido_detalle_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comprometido_detalle
    ADD CONSTRAINT comprometido_detalle_pkey PRIMARY KEY (id);


--
-- Name: comprometidos comprometidos_folio_num_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comprometidos
    ADD CONSTRAINT comprometidos_folio_num_uk UNIQUE (folio_num);


--
-- Name: comprometidos comprometidos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comprometidos
    ADD CONSTRAINT comprometidos_pkey PRIMARY KEY (id);


--
-- Name: dauxiliar dauxiliar_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dauxiliar
    ADD CONSTRAINT dauxiliar_pkey PRIMARY KEY (id);


--
-- Name: devengado_detalle devengado_detalle_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devengado_detalle
    ADD CONSTRAINT devengado_detalle_pkey PRIMARY KEY (id);


--
-- Name: devengados devengados_folio_num_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devengados
    ADD CONSTRAINT devengados_folio_num_uk UNIQUE (folio_num);


--
-- Name: devengados devengados_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devengados
    ADD CONSTRAINT devengados_pkey PRIMARY KEY (id);


--
-- Name: dgeneral dgeneral_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dgeneral
    ADD CONSTRAINT dgeneral_pkey PRIMARY KEY (id);


--
-- Name: expedientes_entrega expedientes_entrega_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expedientes_entrega
    ADD CONSTRAINT expedientes_entrega_pkey PRIMARY KEY (id);


--
-- Name: expedientes_entrega expedientes_entrega_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expedientes_entrega
    ADD CONSTRAINT expedientes_entrega_uk UNIQUE (anio, mes, folio);


--
-- Name: fuentes fuentes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fuentes
    ADD CONSTRAINT fuentes_pkey PRIMARY KEY (id);


--
-- Name: gastos_detalle gastos_detalle_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gastos_detalle
    ADD CONSTRAINT gastos_detalle_pkey PRIMARY KEY (id);


--
-- Name: metas metas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metas
    ADD CONSTRAINT metas_pkey PRIMARY KEY (id);


--
-- Name: partidas_permitidas partidas_permitidas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partidas_permitidas
    ADD CONSTRAINT partidas_permitidas_pkey PRIMARY KEY (id);


--
-- Name: partidas partidas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partidas
    ADD CONSTRAINT partidas_pkey PRIMARY KEY (id);


--
-- Name: partidas_presupuesto partidas_presupuesto_id_usuario_partida_clave_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partidas_presupuesto
    ADD CONSTRAINT partidas_presupuesto_id_usuario_partida_clave_key UNIQUE (id_usuario, partida_clave);


--
-- Name: partidas_presupuesto partidas_presupuesto_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partidas_presupuesto
    ADD CONSTRAINT partidas_presupuesto_pkey PRIMARY KEY (id);


--
-- Name: presupuesto_base_partidas presupuesto_base_partidas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presupuesto_base_partidas
    ADD CONSTRAINT presupuesto_base_partidas_pkey PRIMARY KEY (id);


--
-- Name: presupuesto_detalle presupuesto_detalle_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presupuesto_detalle
    ADD CONSTRAINT presupuesto_detalle_pkey PRIMARY KEY (id);


--
-- Name: presupuesto_detalle presupuesto_detalle_uk_partida_mes; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presupuesto_detalle
    ADD CONSTRAINT presupuesto_detalle_uk_partida_mes UNIQUE (partida, mes);


--
-- Name: programas programas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.programas
    ADD CONSTRAINT programas_pkey PRIMARY KEY (id);


--
-- Name: proyectos_fuentes_permitidas proyectos_fuentes_permitidas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proyectos_fuentes_permitidas
    ADD CONSTRAINT proyectos_fuentes_permitidas_pkey PRIMARY KEY (id);


--
-- Name: proyectos proyectos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proyectos
    ADD CONSTRAINT proyectos_pkey PRIMARY KEY (id);


--
-- Name: reconduccion_oficios reconduccion_oficios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconduccion_oficios
    ADD CONSTRAINT reconduccion_oficios_pkey PRIMARY KEY (id);


--
-- Name: reconducciones_claves reconducciones_claves_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_claves
    ADD CONSTRAINT reconducciones_claves_pkey PRIMARY KEY (id);


--
-- Name: reconducciones_lados reconducciones_lados_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_lados
    ADD CONSTRAINT reconducciones_lados_pkey PRIMARY KEY (id);


--
-- Name: reconducciones_metas reconducciones_metas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_metas
    ADD CONSTRAINT reconducciones_metas_pkey PRIMARY KEY (id);


--
-- Name: reconducciones_movimientos reconducciones_movimientos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_movimientos
    ADD CONSTRAINT reconducciones_movimientos_pkey PRIMARY KEY (id);


--
-- Name: reconducciones reconducciones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones
    ADD CONSTRAINT reconducciones_pkey PRIMARY KEY (id);


--
-- Name: reconducciones_recursos reconducciones_recursos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_recursos
    ADD CONSTRAINT reconducciones_recursos_pkey PRIMARY KEY (id);


--
-- Name: reconducciones_sesiones reconducciones_sesiones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_sesiones
    ADD CONSTRAINT reconducciones_sesiones_pkey PRIMARY KEY (token);


--
-- Name: roles roles_clave_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_clave_key UNIQUE (clave);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: suficiencia_detalle_audit suficiencia_detalle_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suficiencia_detalle_audit
    ADD CONSTRAINT suficiencia_detalle_audit_pkey PRIMARY KEY (audit_id);


--
-- Name: suficiencia_detalle suficiencia_detalle_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suficiencia_detalle
    ADD CONSTRAINT suficiencia_detalle_pkey PRIMARY KEY (id);


--
-- Name: suficiencias_audit suficiencias_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suficiencias_audit
    ADD CONSTRAINT suficiencias_audit_pkey PRIMARY KEY (audit_id);


--
-- Name: suficiencias suficiencias_folio_num_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suficiencias
    ADD CONSTRAINT suficiencias_folio_num_uk UNIQUE (folio_num);


--
-- Name: suficiencias suficiencias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suficiencias
    ADD CONSTRAINT suficiencias_pkey PRIMARY KEY (id);


--
-- Name: comprometido_detalle uk_cp_renglon; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comprometido_detalle
    ADD CONSTRAINT uk_cp_renglon UNIQUE (id_comprometido, renglon);


--
-- Name: devengado_detalle uk_dv_renglon; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devengado_detalle
    ADD CONSTRAINT uk_dv_renglon UNIQUE (id_devengado, renglon);


--
-- Name: partidas_permitidas uk_partidas_permitidas; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partidas_permitidas
    ADD CONSTRAINT uk_partidas_permitidas UNIQUE (dgeneral_clave, dauxiliar_clave, proyecto_clave, fuente_clave, partida_clave);


--
-- Name: proyectos_fuentes_permitidas uk_pf_perm; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proyectos_fuentes_permitidas
    ADD CONSTRAINT uk_pf_perm UNIQUE (dgeneral_clave, dauxiliar_clave, proyecto_clave, fuente_clave);


--
-- Name: suficiencia_detalle uk_suf_renglon; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suficiencia_detalle
    ADD CONSTRAINT uk_suf_renglon UNIQUE (id_suficiencia, renglon);


--
-- Name: presupuesto_base_partidas uq_presupuesto_base; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presupuesto_base_partidas
    ADD CONSTRAINT uq_presupuesto_base UNIQUE (ejercicio, id_dgeneral, id_dauxiliar, id_fuente, id_partida);


--
-- Name: reconducciones_lados uq_reconducciones_lado; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_lados
    ADD CONSTRAINT uq_reconducciones_lado UNIQUE (id_reconduccion, lado);


--
-- Name: usuario_rol usuario_rol_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_rol
    ADD CONSTRAINT usuario_rol_pkey PRIMARY KEY (id_usuario, id_rol);


--
-- Name: usuarios_audit usuarios_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios_audit
    ADD CONSTRAINT usuarios_audit_pkey PRIMARY KEY (audit_id);


--
-- Name: usuarios usuarios_correo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_correo_key UNIQUE (correo);


--
-- Name: usuarios usuarios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_pkey PRIMARY KEY (id);


--
-- Name: usuarios usuarios_usuario_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_usuario_key UNIQUE (usuario);


--
-- Name: idx_audit_eventos_entidad; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_eventos_entidad ON public.auditoria_eventos USING btree (entidad, entidad_id);


--
-- Name: idx_auditoria_eventos_actor_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auditoria_eventos_actor_created_at ON public.auditoria_eventos USING btree (actor_id, created_at DESC);


--
-- Name: idx_auditoria_eventos_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auditoria_eventos_created_at ON public.auditoria_eventos USING btree (created_at DESC);


--
-- Name: idx_auditoria_eventos_tipo_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auditoria_eventos_tipo_created_at ON public.auditoria_eventos USING btree (tipo, created_at DESC);


--
-- Name: idx_comp_suf_estatus; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comp_suf_estatus ON public.comprometidos USING btree (id_suficiencia, estatus);


--
-- Name: idx_comprometido_detalle_id_comprometido; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comprometido_detalle_id_comprometido ON public.comprometido_detalle USING btree (id_comprometido);


--
-- Name: idx_comprometidos_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comprometidos_created_at ON public.comprometidos USING btree (created_at);


--
-- Name: idx_comprometidos_dg_da; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comprometidos_dg_da ON public.comprometidos USING btree (id_dgeneral, id_dauxiliar);


--
-- Name: idx_comprometidos_id_suficiencia; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comprometidos_id_suficiencia ON public.comprometidos USING btree (id_suficiencia);


--
-- Name: idx_comprometidos_mes_pago_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comprometidos_mes_pago_date ON public.comprometidos USING btree (mes_pago_date);


--
-- Name: idx_comprometidos_no; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comprometidos_no ON public.comprometidos USING btree (no_comprometido);


--
-- Name: idx_comprometidos_suf; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comprometidos_suf ON public.comprometidos USING btree (id_suficiencia);


--
-- Name: idx_cp_detalle_comp_clave; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cp_detalle_comp_clave ON public.comprometido_detalle USING btree (id_comprometido, clave);


--
-- Name: idx_cp_detalle_cp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cp_detalle_cp ON public.comprometido_detalle USING btree (id_comprometido);


--
-- Name: idx_dev_comp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dev_comp ON public.devengados USING btree (id_comprometido);


--
-- Name: idx_dev_dg_da; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dev_dg_da ON public.devengados USING btree (id_dgeneral, id_dauxiliar);


--
-- Name: idx_dev_no; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dev_no ON public.devengados USING btree (no_devengado);


--
-- Name: idx_dev_suf; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dev_suf ON public.devengados USING btree (id_suficiencia);


--
-- Name: idx_devengado_detalle_id_devengado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_devengado_detalle_id_devengado ON public.devengado_detalle USING btree (id_devengado);


--
-- Name: idx_devengados_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_devengados_created_at ON public.devengados USING btree (created_at);


--
-- Name: idx_devengados_id_comprometido; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_devengados_id_comprometido ON public.devengados USING btree (id_comprometido);


--
-- Name: idx_devengados_id_suficiencia; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_devengados_id_suficiencia ON public.devengados USING btree (id_suficiencia);


--
-- Name: idx_devengados_mes_pago_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_devengados_mes_pago_date ON public.devengados USING btree (mes_pago_date);


--
-- Name: idx_dv_detalle_dev_clave; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dv_detalle_dev_clave ON public.devengado_detalle USING btree (id_devengado, clave);


--
-- Name: idx_dv_detalle_dv; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dv_detalle_dv ON public.devengado_detalle USING btree (id_devengado);


--
-- Name: idx_entrega_folio; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entrega_folio ON public.expedientes_entrega USING btree (folio);


--
-- Name: idx_entrega_periodo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entrega_periodo ON public.expedientes_entrega USING btree (anio, mes);


--
-- Name: idx_entrega_refs; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entrega_refs ON public.expedientes_entrega USING btree (id_suficiencia, id_comprometido, id_devengado);


--
-- Name: idx_metas_activo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_metas_activo ON public.metas USING btree (activo) WHERE (activo = true);


--
-- Name: idx_metas_programaticas; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_metas_programaticas ON public.metas USING btree (dg_clave, da_clave, proy_clave, conac);


--
-- Name: idx_partidas_permitidas_dg_da; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_partidas_permitidas_dg_da ON public.partidas_permitidas USING btree (dgeneral_clave, dauxiliar_clave);


--
-- Name: idx_partidas_permitidas_fuente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_partidas_permitidas_fuente ON public.partidas_permitidas USING btree (fuente_clave);


--
-- Name: idx_partidas_permitidas_partida; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_partidas_permitidas_partida ON public.partidas_permitidas USING btree (partida_clave);


--
-- Name: idx_partidas_permitidas_proyecto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_partidas_permitidas_proyecto ON public.partidas_permitidas USING btree (proyecto_clave);


--
-- Name: idx_pbp_saldo_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pbp_saldo_lookup ON public.presupuesto_base_partidas USING btree (id_dgeneral, id_dauxiliar, id_fuente, id_proyecto, ejercicio);


--
-- Name: idx_pf_perm_dg_da; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pf_perm_dg_da ON public.proyectos_fuentes_permitidas USING btree (dgeneral_clave, dauxiliar_clave);


--
-- Name: idx_pf_perm_proy_ff; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pf_perm_proy_ff ON public.proyectos_fuentes_permitidas USING btree (proyecto_clave, fuente_clave);


--
-- Name: idx_pp_dg_da_proy_fuente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pp_dg_da_proy_fuente ON public.partidas_permitidas USING btree (dgeneral_clave, dauxiliar_clave, proyecto_clave, fuente_clave);


--
-- Name: idx_recon_ejercicio_estatus; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_recon_ejercicio_estatus ON public.reconducciones USING btree (ejercicio, estatus);


--
-- Name: idx_reconduccion_oficios_id_rc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reconduccion_oficios_id_rc ON public.reconduccion_oficios USING btree (id_reconduccion);


--
-- Name: idx_reconducciones_estatus_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reconducciones_estatus_fecha ON public.reconducciones USING btree (estatus, fecha_elaboracion);


--
-- Name: idx_reconducciones_lados_reconduccion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reconducciones_lados_reconduccion ON public.reconducciones_lados USING btree (id_reconduccion);


--
-- Name: idx_reconducciones_mov_partida_mes_ej; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reconducciones_mov_partida_mes_ej ON public.reconducciones_movimientos USING btree (id_partida, mes_pago_date, ejercicio);


--
-- Name: idx_reconducciones_mov_reconduccion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reconducciones_mov_reconduccion ON public.reconducciones_movimientos USING btree (id_reconduccion);


--
-- Name: idx_reconducciones_recursos_reconduccion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reconducciones_recursos_reconduccion ON public.reconducciones_recursos USING btree (id_reconduccion);


--
-- Name: idx_suf_audit_actor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_suf_audit_actor ON public.suficiencias_audit USING btree (actor_id);


--
-- Name: idx_suf_audit_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_suf_audit_fecha ON public.suficiencias_audit USING btree (fecha);


--
-- Name: idx_suf_audit_sufid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_suf_audit_sufid ON public.suficiencias_audit USING btree (suficiencia_id);


--
-- Name: idx_suf_cancelled_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_suf_cancelled_at ON public.suficiencias USING btree (cancelled_at);


--
-- Name: idx_suf_detalle_clave; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_suf_detalle_clave ON public.suficiencia_detalle USING btree (clave);


--
-- Name: idx_suf_detalle_id_suficiencia; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_suf_detalle_id_suficiencia ON public.suficiencia_detalle USING btree (id_suficiencia);


--
-- Name: idx_suf_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_suf_expires_at ON public.suficiencias USING btree (expires_at);


--
-- Name: idx_suf_id_dgeneral; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_suf_id_dgeneral ON public.suficiencias USING btree (id_dgeneral);


--
-- Name: idx_suf_id_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_suf_id_usuario ON public.suficiencias USING btree (id_usuario);


--
-- Name: idx_suf_saldo_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_suf_saldo_lookup ON public.suficiencias USING btree (id_dgeneral, id_dauxiliar, id_fuente, id_proyecto, mes_pago) WHERE (cancelled_at IS NULL);


--
-- Name: idx_sufdet_audit_actor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sufdet_audit_actor ON public.suficiencia_detalle_audit USING btree (actor_id);


--
-- Name: idx_sufdet_audit_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sufdet_audit_fecha ON public.suficiencia_detalle_audit USING btree (fecha);


--
-- Name: idx_sufdet_audit_sufid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sufdet_audit_sufid ON public.suficiencia_detalle_audit USING btree (suficiencia_id);


--
-- Name: idx_suficiencias_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_suficiencias_created_at ON public.suficiencias USING btree (created_at);


--
-- Name: idx_suficiencias_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_suficiencias_expires_at ON public.suficiencias USING btree (expires_at);


--
-- Name: idx_suficiencias_mes_pago_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_suficiencias_mes_pago_date ON public.suficiencias USING btree (mes_pago_date);


--
-- Name: idx_usuarios_activo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_usuarios_activo ON public.usuarios USING btree (activo) WHERE (activo = true);


--
-- Name: reconducciones_claves_clave_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX reconducciones_claves_clave_key ON public.reconducciones_claves USING btree (clave);


--
-- Name: uq_dauxiliar_clave; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_dauxiliar_clave ON public.dauxiliar USING btree (clave);


--
-- Name: uq_fuentes_clave; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_fuentes_clave ON public.fuentes USING btree (clave);


--
-- Name: uq_partida_usuario_ejercicio; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_partida_usuario_ejercicio ON public.partidas_presupuesto USING btree (id_usuario, partida_clave, ejercicio);


--
-- Name: uq_partidas_clave; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_partidas_clave ON public.partidas USING btree (clave);


--
-- Name: uq_proyectos_clave; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_proyectos_clave ON public.proyectos USING btree (clave);


--
-- Name: suficiencias set_suf_expires_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_suf_expires_at BEFORE INSERT ON public.suficiencias FOR EACH ROW EXECUTE FUNCTION public.trg_set_suf_expires_at();


--
-- Name: suficiencia_detalle trg_audit_suficiencia_detalle; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_suficiencia_detalle AFTER INSERT OR DELETE OR UPDATE ON public.suficiencia_detalle FOR EACH ROW EXECUTE FUNCTION public.trg_suficiencia_detalle_audit();


--
-- Name: suficiencias trg_audit_suficiencias; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_suficiencias AFTER INSERT OR DELETE OR UPDATE ON public.suficiencias FOR EACH ROW EXECUTE FUNCTION public.trg_suficiencias_audit();


--
-- Name: expedientes_entrega trg_expedientes_entrega_auto_populate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_expedientes_entrega_auto_populate BEFORE INSERT OR UPDATE ON public.expedientes_entrega FOR EACH ROW EXECUTE FUNCTION public.fn_expedientes_entrega_auto_populate();


--
-- Name: expedientes_entrega trg_expedientes_entrega_updated; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_expedientes_entrega_updated BEFORE UPDATE ON public.expedientes_entrega FOR EACH ROW EXECUTE FUNCTION public.fn_set_actualizado_en();


--
-- Name: comprometidos trg_set_mes_pago_date_comp; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_mes_pago_date_comp BEFORE INSERT OR UPDATE OF mes_pago ON public.comprometidos FOR EACH ROW EXECUTE FUNCTION public.trg_set_mes_pago_date();


--
-- Name: devengados trg_set_mes_pago_date_dev; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_mes_pago_date_dev BEFORE INSERT OR UPDATE OF mes_pago ON public.devengados FOR EACH ROW EXECUTE FUNCTION public.trg_set_mes_pago_date();


--
-- Name: suficiencias trg_set_mes_pago_date_suf; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_mes_pago_date_suf BEFORE INSERT OR UPDATE OF mes_pago ON public.suficiencias FOR EACH ROW EXECUTE FUNCTION public.trg_set_mes_pago_date();


--
-- Name: suficiencias trg_set_no_suficiencia; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_no_suficiencia BEFORE INSERT ON public.suficiencias FOR EACH ROW EXECUTE FUNCTION public.fn_set_no_suficiencia();


--
-- Name: usuarios trg_usuarios_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_usuarios_audit AFTER INSERT OR DELETE OR UPDATE ON public.usuarios FOR EACH ROW EXECUTE FUNCTION public.fn_usuarios_audit();


--
-- Name: comprometido_detalle fk_comprometido_detalle_comp; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comprometido_detalle
    ADD CONSTRAINT fk_comprometido_detalle_comp FOREIGN KEY (id_comprometido) REFERENCES public.comprometidos(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: comprometidos fk_comprometidos_dauxiliar; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comprometidos
    ADD CONSTRAINT fk_comprometidos_dauxiliar FOREIGN KEY (id_dauxiliar) REFERENCES public.dauxiliar(id);


--
-- Name: comprometidos fk_comprometidos_dgeneral; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comprometidos
    ADD CONSTRAINT fk_comprometidos_dgeneral FOREIGN KEY (id_dgeneral) REFERENCES public.dgeneral(id);


--
-- Name: comprometidos fk_comprometidos_fuente; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comprometidos
    ADD CONSTRAINT fk_comprometidos_fuente FOREIGN KEY (id_fuente) REFERENCES public.fuentes(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: comprometidos fk_comprometidos_impuesto_tipo; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comprometidos
    ADD CONSTRAINT fk_comprometidos_impuesto_tipo FOREIGN KEY (impuesto_tipo) REFERENCES public.cat_impuesto_tipo(clave);


--
-- Name: comprometidos fk_comprometidos_proyecto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comprometidos
    ADD CONSTRAINT fk_comprometidos_proyecto FOREIGN KEY (id_proyecto) REFERENCES public.proyectos(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: comprometidos fk_comprometidos_suf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comprometidos
    ADD CONSTRAINT fk_comprometidos_suf FOREIGN KEY (id_suficiencia) REFERENCES public.suficiencias(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: comprometidos fk_comprometidos_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comprometidos
    ADD CONSTRAINT fk_comprometidos_usuario FOREIGN KEY (id_usuario) REFERENCES public.usuarios(id);


--
-- Name: devengados fk_dev_comp; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devengados
    ADD CONSTRAINT fk_dev_comp FOREIGN KEY (id_comprometido) REFERENCES public.comprometidos(id) ON DELETE RESTRICT;


--
-- Name: devengados fk_dev_suf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devengados
    ADD CONSTRAINT fk_dev_suf FOREIGN KEY (id_suficiencia) REFERENCES public.suficiencias(id) ON DELETE RESTRICT;


--
-- Name: devengado_detalle fk_devengado_detalle_dev; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devengado_detalle
    ADD CONSTRAINT fk_devengado_detalle_dev FOREIGN KEY (id_devengado) REFERENCES public.devengados(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: devengados fk_devengados_dauxiliar; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devengados
    ADD CONSTRAINT fk_devengados_dauxiliar FOREIGN KEY (id_dauxiliar) REFERENCES public.dauxiliar(id);


--
-- Name: devengados fk_devengados_dgeneral; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devengados
    ADD CONSTRAINT fk_devengados_dgeneral FOREIGN KEY (id_dgeneral) REFERENCES public.dgeneral(id);


--
-- Name: devengados fk_devengados_fuente; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devengados
    ADD CONSTRAINT fk_devengados_fuente FOREIGN KEY (id_fuente) REFERENCES public.fuentes(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: devengados fk_devengados_impuesto_tipo; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devengados
    ADD CONSTRAINT fk_devengados_impuesto_tipo FOREIGN KEY (impuesto_tipo) REFERENCES public.cat_impuesto_tipo(clave);


--
-- Name: devengados fk_devengados_proyecto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devengados
    ADD CONSTRAINT fk_devengados_proyecto FOREIGN KEY (id_proyecto) REFERENCES public.proyectos(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: devengados fk_devengados_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devengados
    ADD CONSTRAINT fk_devengados_usuario FOREIGN KEY (id_usuario) REFERENCES public.usuarios(id);


--
-- Name: expedientes_entrega fk_expedientes_comprometido; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expedientes_entrega
    ADD CONSTRAINT fk_expedientes_comprometido FOREIGN KEY (id_comprometido) REFERENCES public.comprometidos(id) ON DELETE SET NULL;


--
-- Name: expedientes_entrega fk_expedientes_dauxiliar; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expedientes_entrega
    ADD CONSTRAINT fk_expedientes_dauxiliar FOREIGN KEY (id_dauxiliar) REFERENCES public.dauxiliar(id) ON DELETE SET NULL;


--
-- Name: expedientes_entrega fk_expedientes_devengado; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expedientes_entrega
    ADD CONSTRAINT fk_expedientes_devengado FOREIGN KEY (id_devengado) REFERENCES public.devengados(id) ON DELETE SET NULL;


--
-- Name: expedientes_entrega fk_expedientes_dgeneral; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expedientes_entrega
    ADD CONSTRAINT fk_expedientes_dgeneral FOREIGN KEY (id_dgeneral) REFERENCES public.dgeneral(id) ON DELETE SET NULL;


--
-- Name: expedientes_entrega fk_expedientes_partida_clave; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expedientes_entrega
    ADD CONSTRAINT fk_expedientes_partida_clave FOREIGN KEY (partida_clave) REFERENCES public.partidas(clave) ON DELETE SET NULL;


--
-- Name: expedientes_entrega fk_expedientes_suficiencia; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expedientes_entrega
    ADD CONSTRAINT fk_expedientes_suficiencia FOREIGN KEY (id_suficiencia) REFERENCES public.suficiencias(id) ON DELETE SET NULL;


--
-- Name: proyectos_fuentes_permitidas fk_pf_perm_dgeneral_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proyectos_fuentes_permitidas
    ADD CONSTRAINT fk_pf_perm_dgeneral_id FOREIGN KEY (dgeneral_id) REFERENCES public.dgeneral(id);


--
-- Name: reconducciones_lados fk_reconducciones_lados_dauxiliar; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_lados
    ADD CONSTRAINT fk_reconducciones_lados_dauxiliar FOREIGN KEY (id_dauxiliar) REFERENCES public.dauxiliar(id);


--
-- Name: reconducciones_lados fk_reconducciones_lados_dgeneral; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_lados
    ADD CONSTRAINT fk_reconducciones_lados_dgeneral FOREIGN KEY (id_dgeneral) REFERENCES public.dgeneral(id);


--
-- Name: reconducciones_lados fk_reconducciones_lados_fuentes; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_lados
    ADD CONSTRAINT fk_reconducciones_lados_fuentes FOREIGN KEY (id_fuente) REFERENCES public.fuentes(id);


--
-- Name: reconducciones_lados fk_reconducciones_lados_programas; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_lados
    ADD CONSTRAINT fk_reconducciones_lados_programas FOREIGN KEY (id_programa) REFERENCES public.programas(id);


--
-- Name: reconducciones_lados fk_reconducciones_lados_proyectos; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_lados
    ADD CONSTRAINT fk_reconducciones_lados_proyectos FOREIGN KEY (id_proyecto) REFERENCES public.proyectos(id);


--
-- Name: reconducciones_lados fk_reconducciones_lados_reconduccion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_lados
    ADD CONSTRAINT fk_reconducciones_lados_reconduccion FOREIGN KEY (id_reconduccion) REFERENCES public.reconducciones(id);


--
-- Name: reconducciones_metas fk_reconducciones_metas_reconduccion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_metas
    ADD CONSTRAINT fk_reconducciones_metas_reconduccion FOREIGN KEY (id_reconduccion) REFERENCES public.reconducciones(id);


--
-- Name: reconducciones_movimientos fk_reconducciones_mov_dauxiliar; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_movimientos
    ADD CONSTRAINT fk_reconducciones_mov_dauxiliar FOREIGN KEY (id_dauxiliar) REFERENCES public.dauxiliar(id);


--
-- Name: reconducciones_movimientos fk_reconducciones_mov_dgeneral; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_movimientos
    ADD CONSTRAINT fk_reconducciones_mov_dgeneral FOREIGN KEY (id_dgeneral) REFERENCES public.dgeneral(id);


--
-- Name: reconducciones_movimientos fk_reconducciones_mov_fuente; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_movimientos
    ADD CONSTRAINT fk_reconducciones_mov_fuente FOREIGN KEY (id_fuente) REFERENCES public.fuentes(id);


--
-- Name: reconducciones_movimientos fk_reconducciones_mov_partida; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_movimientos
    ADD CONSTRAINT fk_reconducciones_mov_partida FOREIGN KEY (id_partida) REFERENCES public.partidas(id);


--
-- Name: reconducciones_movimientos fk_reconducciones_mov_proyecto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_movimientos
    ADD CONSTRAINT fk_reconducciones_mov_proyecto FOREIGN KEY (id_proyecto) REFERENCES public.proyectos(id);


--
-- Name: reconducciones_movimientos fk_reconducciones_mov_reconduccion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_movimientos
    ADD CONSTRAINT fk_reconducciones_mov_reconduccion FOREIGN KEY (id_reconduccion) REFERENCES public.reconducciones(id);


--
-- Name: reconducciones_recursos fk_reconducciones_recursos_partida; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_recursos
    ADD CONSTRAINT fk_reconducciones_recursos_partida FOREIGN KEY (id_partida) REFERENCES public.partidas(id);


--
-- Name: reconducciones_recursos fk_reconducciones_recursos_reconduccion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconducciones_recursos
    ADD CONSTRAINT fk_reconducciones_recursos_reconduccion FOREIGN KEY (id_reconduccion) REFERENCES public.reconducciones(id);


--
-- Name: suficiencia_detalle fk_suf_det; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suficiencia_detalle
    ADD CONSTRAINT fk_suf_det FOREIGN KEY (id_suficiencia) REFERENCES public.suficiencias(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: suficiencias fk_suf_usuarios; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suficiencias
    ADD CONSTRAINT fk_suf_usuarios FOREIGN KEY (id_usuario) REFERENCES public.usuarios(id);


--
-- Name: suficiencias fk_suficiencias_dauxiliar; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suficiencias
    ADD CONSTRAINT fk_suficiencias_dauxiliar FOREIGN KEY (id_dauxiliar) REFERENCES public.dauxiliar(id);


--
-- Name: suficiencias fk_suficiencias_dgeneral; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suficiencias
    ADD CONSTRAINT fk_suficiencias_dgeneral FOREIGN KEY (id_dgeneral) REFERENCES public.dgeneral(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: suficiencias fk_suficiencias_fuente; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suficiencias
    ADD CONSTRAINT fk_suficiencias_fuente FOREIGN KEY (id_fuente) REFERENCES public.fuentes(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: suficiencias fk_suficiencias_impuesto_tipo; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suficiencias
    ADD CONSTRAINT fk_suficiencias_impuesto_tipo FOREIGN KEY (impuesto_tipo) REFERENCES public.cat_impuesto_tipo(clave);


--
-- Name: suficiencias fk_suficiencias_proyecto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suficiencias
    ADD CONSTRAINT fk_suficiencias_proyecto FOREIGN KEY (id_proyecto) REFERENCES public.proyectos(id);


--
-- Name: usuario_rol fk_usuario_rol_rol; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_rol
    ADD CONSTRAINT fk_usuario_rol_rol FOREIGN KEY (id_rol) REFERENCES public.roles(id) ON DELETE CASCADE;


--
-- Name: usuarios fk_usuarios_updated_by; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT fk_usuarios_updated_by FOREIGN KEY (updated_by) REFERENCES public.usuarios(id);


--
-- Name: gastos_detalle gastos_detalle_id_fuente_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gastos_detalle
    ADD CONSTRAINT gastos_detalle_id_fuente_fkey FOREIGN KEY (id_fuente) REFERENCES public.fuentes(id);


--
-- Name: partidas_presupuesto partidas_presupuesto_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partidas_presupuesto
    ADD CONSTRAINT partidas_presupuesto_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuarios(id);


--
-- Name: presupuesto_base_partidas presupuesto_base_partidas_id_dauxiliar_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presupuesto_base_partidas
    ADD CONSTRAINT presupuesto_base_partidas_id_dauxiliar_fkey FOREIGN KEY (id_dauxiliar) REFERENCES public.dauxiliar(id);


--
-- Name: presupuesto_base_partidas presupuesto_base_partidas_id_dgeneral_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presupuesto_base_partidas
    ADD CONSTRAINT presupuesto_base_partidas_id_dgeneral_fkey FOREIGN KEY (id_dgeneral) REFERENCES public.dgeneral(id);


--
-- Name: presupuesto_base_partidas presupuesto_base_partidas_id_fuente_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presupuesto_base_partidas
    ADD CONSTRAINT presupuesto_base_partidas_id_fuente_fkey FOREIGN KEY (id_fuente) REFERENCES public.fuentes(id);


--
-- Name: presupuesto_base_partidas presupuesto_base_partidas_id_partida_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presupuesto_base_partidas
    ADD CONSTRAINT presupuesto_base_partidas_id_partida_fkey FOREIGN KEY (id_partida) REFERENCES public.partidas(id);


--
-- Name: presupuesto_base_partidas presupuesto_base_partidas_id_proyecto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presupuesto_base_partidas
    ADD CONSTRAINT presupuesto_base_partidas_id_proyecto_fkey FOREIGN KEY (id_proyecto) REFERENCES public.proyectos(id);


--
-- Name: presupuesto_detalle presupuesto_detalle_fuente_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presupuesto_detalle
    ADD CONSTRAINT presupuesto_detalle_fuente_fk FOREIGN KEY (id_fuente) REFERENCES public.fuentes(id);


--
-- Name: reconduccion_oficios reconduccion_oficios_id_reconduccion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconduccion_oficios
    ADD CONSTRAINT reconduccion_oficios_id_reconduccion_fkey FOREIGN KEY (id_reconduccion) REFERENCES public.reconducciones(id) ON DELETE CASCADE;


--
-- Name: reconduccion_oficios reconduccion_oficios_subido_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconduccion_oficios
    ADD CONSTRAINT reconduccion_oficios_subido_por_fkey FOREIGN KEY (subido_por) REFERENCES public.usuarios(id) ON DELETE SET NULL;


--
-- PostgreSQL database dump complete
--

\unrestrict 0IB7hlcU5Qdh1dK7lS1qyKiKAqv3dSrK8Yu4CSUyq6lXgCL8tASd1NKBXTM8VPA

