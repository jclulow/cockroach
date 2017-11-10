//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
// implied. See the License for the specific language governing
// permissions and limitations under the License.

// Portions Copyright (c) 1996-2015, PostgreSQL Global Development Group
// Portions Copyright (c) 1994, Regents of the University of California

%{
package parser

import (
    "fmt"

    "go/constant"
    "go/token"

    "github.com/cockroachdb/cockroach/pkg/sql/coltypes"
    "github.com/cockroachdb/cockroach/pkg/sql/lex"
    "github.com/cockroachdb/cockroach/pkg/sql/privilege"
)

// MaxUint is the maximum value of an uint.
const MaxUint = ^uint(0)
// MaxInt is the maximum value of an int.
const MaxInt = int(MaxUint >> 1)

func unimplemented(sqllex sqlLexer, feature string) int {
    sqllex.(*Scanner).Unimplemented(feature)
    return 1
}

func unimplementedWithIssue(sqllex sqlLexer, issue int) int {
    sqllex.(*Scanner).UnimplementedWithIssue(issue)
    return 1
}
%}

%{
// sqlSymUnion represents a union of types, providing accessor methods
// to retrieve the underlying type stored in the union's empty interface.
// The purpose of the sqlSymUnion struct is to reduce the memory footprint of
// the sqlSymType because only one value (of a variety of types) is ever needed
// to be stored in the union field at a time.
//
// By using an empty interface, we lose the type checking previously provided
// by yacc and the Go compiler when dealing with union values. Instead, runtime
// type assertions must be relied upon in the methods below, and as such, the
// parser should be thoroughly tested whenever new syntax is added.
//
// It is important to note that when assigning values to sqlSymUnion.val, all
// nil values should be typed so that they are stored as nil instances in the
// empty interface, instead of setting the empty interface to nil. This means
// that:
//     $$ = []String(nil)
// should be used, instead of:
//     $$ = nil
// to assign a nil string slice to the union.
type sqlSymUnion struct {
    val interface{}
}

// The following accessor methods come in three forms, depending on the
// type of the value being accessed and whether a nil value is admissible
// for the corresponding grammar rule.
// - Values and pointers are directly type asserted from the empty
//   interface, regardless of whether a nil value is admissible or
//   not. A panic occurs if the type assertion is incorrect; no panic occurs
//   if a nil is not expected but present. (TODO(knz): split this category of
//   accessor in two; with one checking for unexpected nils.)
//   Examples: bool(), tableWithIdx().
//
// - Interfaces where a nil is admissible are handled differently
//   because a nil instance of an interface inserted into the empty interface
//   becomes a nil instance of the empty interface and therefore will fail a
//   direct type assertion. Instead, a guarded type assertion must be used,
//   which returns nil if the type assertion fails.
//   Examples: expr(), stmt().
//
// - Interfaces where a nil is not admissible are implemented as a direct
//   type assertion, which causes a panic to occur if an unexpected nil
//   is encountered.
//   Examples: namePart(), tblDef().
//
func (u *sqlSymUnion) numVal() *NumVal {
    return u.val.(*NumVal)
}
func (u *sqlSymUnion) strVal() *StrVal {
    if stmt, ok := u.val.(*StrVal); ok {
        return stmt
    }
    return nil
}
func (u *sqlSymUnion) bool() bool {
    return u.val.(bool)
}
func (u *sqlSymUnion) strPtr() *string {
    return u.val.(*string)
}
func (u *sqlSymUnion) strs() []string {
    return u.val.([]string)
}
func (u *sqlSymUnion) newTableWithIdx() *TableNameWithIndex {
    tn := u.val.(TableNameWithIndex)
    return &tn
}
func (u *sqlSymUnion) tableWithIdx() TableNameWithIndex {
    return u.val.(TableNameWithIndex)
}
func (u *sqlSymUnion) newTableWithIdxList() TableNameWithIndexList {
    return u.val.(TableNameWithIndexList)
}
func (u *sqlSymUnion) namePart() NamePart {
    return u.val.(NamePart)
}
func (u *sqlSymUnion) nameList() NameList {
    return u.val.(NameList)
}
func (u *sqlSymUnion) unresolvedName() UnresolvedName {
    return u.val.(UnresolvedName)
}
func (u *sqlSymUnion) unresolvedNames() UnresolvedNames {
    return u.val.(UnresolvedNames)
}
func (u *sqlSymUnion) functionReference() FunctionReference {
    return u.val.(FunctionReference)
}
func (u *sqlSymUnion) resolvableFunctionReference() ResolvableFunctionReference {
    return ResolvableFunctionReference{u.val.(FunctionReference)}
}
func (u *sqlSymUnion) normalizableTableName() NormalizableTableName {
    return NormalizableTableName{u.val.(TableNameReference)}
}
func (u *sqlSymUnion) newNormalizableTableName() *NormalizableTableName {
    return &NormalizableTableName{u.val.(TableNameReference)}
}
func (u *sqlSymUnion) tablePatterns() TablePatterns {
    return u.val.(TablePatterns)
}
func (u *sqlSymUnion) tableNameReferences() TableNameReferences {
    return u.val.(TableNameReferences)
}
func (u *sqlSymUnion) indexHints() *IndexHints {
    return u.val.(*IndexHints)
}
func (u *sqlSymUnion) arraySubscript() *ArraySubscript {
    return u.val.(*ArraySubscript)
}
func (u *sqlSymUnion) arraySubscripts() ArraySubscripts {
    if as, ok := u.val.(ArraySubscripts); ok {
        return as
    }
    return nil
}
func (u *sqlSymUnion) stmt() Statement {
    if stmt, ok := u.val.(Statement); ok {
        return stmt
    }
    return nil
}
func (u *sqlSymUnion) stmts() []Statement {
    return u.val.([]Statement)
}
func (u *sqlSymUnion) slct() *Select {
    return u.val.(*Select)
}
func (u *sqlSymUnion) selectStmt() SelectStatement {
    return u.val.(SelectStatement)
}
func (u *sqlSymUnion) colDef() *ColumnTableDef {
    return u.val.(*ColumnTableDef)
}
func (u *sqlSymUnion) constraintDef() ConstraintTableDef {
    return u.val.(ConstraintTableDef)
}
func (u *sqlSymUnion) tblDef() TableDef {
    return u.val.(TableDef)
}
func (u *sqlSymUnion) tblDefs() TableDefs {
    return u.val.(TableDefs)
}
func (u *sqlSymUnion) colQual() NamedColumnQualification {
    return u.val.(NamedColumnQualification)
}
func (u *sqlSymUnion) colQualElem() ColumnQualification {
    return u.val.(ColumnQualification)
}
func (u *sqlSymUnion) colQuals() []NamedColumnQualification {
    return u.val.([]NamedColumnQualification)
}
func (u *sqlSymUnion) colType() coltypes.T {
    if colType, ok := u.val.(coltypes.T); ok {
        return colType
    }
    return nil
}
func (u *sqlSymUnion) tableRefCols() []ColumnID {
    if refCols, ok := u.val.([]ColumnID); ok {
        return refCols
    }
    return nil
}
func (u *sqlSymUnion) castTargetType() coltypes.CastTargetType {
    return u.val.(coltypes.CastTargetType)
}
func (u *sqlSymUnion) colTypes() []coltypes.T {
    return u.val.([]coltypes.T)
}
func (u *sqlSymUnion) expr() Expr {
    if expr, ok := u.val.(Expr); ok {
        return expr
    }
    return nil
}
func (u *sqlSymUnion) exprs() Exprs {
    return u.val.(Exprs)
}
func (u *sqlSymUnion) selExpr() SelectExpr {
    return u.val.(SelectExpr)
}
func (u *sqlSymUnion) selExprs() SelectExprs {
    return u.val.(SelectExprs)
}
func (u *sqlSymUnion) retClause() ReturningClause {
	return u.val.(ReturningClause)
}
func (u *sqlSymUnion) aliasClause() AliasClause {
    return u.val.(AliasClause)
}
func (u *sqlSymUnion) asOfClause() AsOfClause {
    return u.val.(AsOfClause)
}
func (u *sqlSymUnion) tblExpr() TableExpr {
    return u.val.(TableExpr)
}
func (u *sqlSymUnion) tblExprs() TableExprs {
    return u.val.(TableExprs)
}
func (u *sqlSymUnion) from() *From {
    return u.val.(*From)
}
func (u *sqlSymUnion) int32s() []int32 {
    return u.val.([]int32)
}
func (u *sqlSymUnion) joinCond() JoinCond {
    return u.val.(JoinCond)
}
func (u *sqlSymUnion) when() *When {
    return u.val.(*When)
}
func (u *sqlSymUnion) whens() []*When {
    return u.val.([]*When)
}
func (u *sqlSymUnion) updateExpr() *UpdateExpr {
    return u.val.(*UpdateExpr)
}
func (u *sqlSymUnion) updateExprs() UpdateExprs {
    return u.val.(UpdateExprs)
}
func (u *sqlSymUnion) limit() *Limit {
    return u.val.(*Limit)
}
func (u *sqlSymUnion) targetList() TargetList {
    return u.val.(TargetList)
}
func (u *sqlSymUnion) targetListPtr() *TargetList {
    return u.val.(*TargetList)
}
func (u *sqlSymUnion) privilegeType() privilege.Kind {
    return u.val.(privilege.Kind)
}
func (u *sqlSymUnion) privilegeList() privilege.List {
    return u.val.(privilege.List)
}
func (u *sqlSymUnion) onConflict() *OnConflict {
    return u.val.(*OnConflict)
}
func (u *sqlSymUnion) orderBy() OrderBy {
    return u.val.(OrderBy)
}
func (u *sqlSymUnion) order() *Order {
    return u.val.(*Order)
}
func (u *sqlSymUnion) orders() []*Order {
    return u.val.([]*Order)
}
func (u *sqlSymUnion) groupBy() GroupBy {
    return u.val.(GroupBy)
}
func (u *sqlSymUnion) dir() Direction {
    return u.val.(Direction)
}
func (u *sqlSymUnion) alterTableCmd() AlterTableCmd {
    return u.val.(AlterTableCmd)
}
func (u *sqlSymUnion) alterTableCmds() AlterTableCmds {
    return u.val.(AlterTableCmds)
}
func (u *sqlSymUnion) isoLevel() IsolationLevel {
    return u.val.(IsolationLevel)
}
func (u *sqlSymUnion) userPriority() UserPriority {
    return u.val.(UserPriority)
}
func (u *sqlSymUnion) readWriteMode() ReadWriteMode {
    return u.val.(ReadWriteMode)
}
func (u *sqlSymUnion) idxElem() IndexElem {
    return u.val.(IndexElem)
}
func (u *sqlSymUnion) idxElems() IndexElemList {
    return u.val.(IndexElemList)
}
func (u *sqlSymUnion) dropBehavior() DropBehavior {
    return u.val.(DropBehavior)
}
func (u *sqlSymUnion) validationBehavior() ValidationBehavior {
    return u.val.(ValidationBehavior)
}
func (u *sqlSymUnion) interleave() *InterleaveDef {
    return u.val.(*InterleaveDef)
}
func (u *sqlSymUnion) partitionBy() *PartitionBy {
    return u.val.(*PartitionBy)
}
func (u *sqlSymUnion) listPartitions() []ListPartition {
    return u.val.([]ListPartition)
}
func (u *sqlSymUnion) rangePartitions() []RangePartition {
    return u.val.([]RangePartition)
}
func (u *sqlSymUnion) tuples() []*Tuple {
    return u.val.([]*Tuple)
}
func (u *sqlSymUnion) windowDef() *WindowDef {
    return u.val.(*WindowDef)
}
func (u *sqlSymUnion) window() Window {
    return u.val.(Window)
}
func (u *sqlSymUnion) op() operator {
    return u.val.(operator)
}
func (u *sqlSymUnion) cmpOp() ComparisonOperator {
    return u.val.(ComparisonOperator)
}
func (u *sqlSymUnion) durationField() durationField {
    return u.val.(durationField)
}
func (u *sqlSymUnion) kvOption() KVOption {
    return u.val.(KVOption)
}
func (u *sqlSymUnion) kvOptions() []KVOption {
    if colType, ok := u.val.([]KVOption); ok {
        return colType
    }
    return nil
}
func (u *sqlSymUnion) transactionModes() TransactionModes {
    return u.val.(TransactionModes)
}
func (u *sqlSymUnion) referenceAction() ReferenceAction {
    return u.val.(ReferenceAction)
}
func (u *sqlSymUnion) referenceActions() ReferenceActions {
    return u.val.(ReferenceActions)
}

func (u *sqlSymUnion) scrubOptions() ScrubOptions {
    return u.val.(ScrubOptions)
}

func (u *sqlSymUnion) scrubOption() ScrubOption {
    return u.val.(ScrubOption)
}

%}

// NB: the %token definitions must come before the %type definitions in this
// file to work around a bug in goyacc. See #16369 for more details.

// Non-keyword token types.
%token <str>   IDENT SCONST BCONST
%token <*NumVal> ICONST FCONST
%token <str>   PLACEHOLDER
%token <str>   TYPECAST TYPEANNOTATE DOT_DOT
%token <str>   LESS_EQUALS GREATER_EQUALS NOT_EQUALS
%token <str>   NOT_REGMATCH REGIMATCH NOT_REGIMATCH
%token <str>   ERROR

// If you want to make any keyword changes, add the new keyword here as well as
// to the appropriate one of the reserved-or-not-so-reserved keyword lists,
// below; search this file for "Keyword category lists".

// Ordinary key words in alphabetical order.
%token <str>   ACTION ADD
%token <str>   ALL ALL_EXISTENCE ALTER ANALYSE ANALYZE AND ANY ANNOTATE_TYPE ARRAY AS ASC
%token <str>   ASYMMETRIC AT

%token <str>   BACKUP BEGIN BETWEEN BIGINT BIGSERIAL BIT
%token <str>   BLOB BOOL BOOLEAN BOTH BY BYTEA BYTES

%token <str>   CANCEL CASCADE CASE CAST CHAR
%token <str>   CHARACTER CHARACTERISTICS CHECK
%token <str>   CLUSTER COALESCE COLLATE COLLATION COLUMN COLUMNS COMMIT
%token <str>   COMMITTED CONCAT CONFIGURATION CONFIGURATIONS CONFIGURE
%token <str>   CONFLICT CONSTRAINT CONSTRAINTS CONTAINS COPY COVERING CREATE
%token <str>   CROSS CSV CUBE CURRENT CURRENT_CATALOG CURRENT_DATE CURRENT_SCHEMA
%token <str>   CURRENT_ROLE CURRENT_TIME CURRENT_TIMESTAMP
%token <str>   CURRENT_USER CYCLE

%token <str>   DATA DATABASE DATABASES DATE DAY DEC DECIMAL DEFAULT
%token <str>   DEALLOCATE DEFERRABLE DELETE DESC
%token <str>   DISCARD DISTINCT DO DOUBLE DROP

%token <str>   ELSE ENCODING END ESCAPE EXCEPT
%token <str>   EXISTS EXECUTE EXPERIMENTAL_FINGERPRINTS EXPERIMENTAL
%token <str>   EXPLAIN EXTRACT EXTRACT_DURATION

%token <str>   FALSE FAMILY FETCH FETCHVAL FETCHTEXT FETCHVAL_PATH FETCHTEXT_PATH FILTER
%token <str>   FIRST FLOAT FLOAT4 FLOAT8 FLOORDIV FOLLOWING FOR FORCE_INDEX FOREIGN FROM FULL

%token <str>   GRANT GRANTS GREATEST GROUP GROUPING

%token <str>   HAVING HELP HIGH HOUR

%token <str>   IMPORT INCREMENTAL IF IFNULL ILIKE IN INET INTERLEAVE
%token <str>   INDEX INDEXES INITIALLY
%token <str>   INNER INSERT INT INT2VECTOR INT2 INT4 INT8 INT64 INTEGER
%token <str>   INTERSECT INTERVAL INTO IS ISOLATION

%token <str>   JOB JOBS JOIN JSON JSONB

%token <str>   KEY KEYS KV

%token <str>   LATERAL LC_CTYPE LC_COLLATE
%token <str>   LEADING LEAST LEFT LESS LEVEL LIKE LIMIT LIST LOCAL
%token <str>   LOCALTIME LOCALTIMESTAMP LOW LSHIFT

%token <str>   MATCH MAXVALUE MINUTE MONTH

%token <str>   NAN NAME NAMES NATURAL NEXT NO NO_INDEX_JOIN NORMAL
%token <str>   NOT NOTHING NULL NULLIF
%token <str>   NULLS NUMERIC

%token <str>   OF OFF OFFSET OID ON ONLY OPTIONS OR
%token <str>   ORDER ORDINALITY OUT OUTER OVER OVERLAPS OVERLAY

%token <str>   PARENT PARTIAL PARTITION PASSWORD PAUSE PHYSICAL PLACING
%token <str>   PLANS POSITION PRECEDING PRECISION PREPARE PRIMARY PRIORITY

%token <str>   QUERIES QUERY

%token <str>   RANGE READ REAL RECURSIVE REF REFERENCES
%token <str>   REGCLASS REGPROC REGPROCEDURE REGNAMESPACE REGTYPE
%token <str>   REMOVE_PATH RENAME REPEATABLE
%token <str>   RELEASE RESET RESTORE RESTRICT RESUME RETURNING REVOKE RIGHT
%token <str>   ROLLBACK ROLLUP ROW ROWS RSHIFT

%token <str>   SAVEPOINT SCATTER SCRUB SEARCH SECOND SELECT SEQUENCES
%token <str>   SERIAL SERIALIZABLE SESSION SESSIONS SESSION_USER SET SETTING SETTINGS
%token <str>   SHOW SIMILAR SIMPLE SMALLINT SMALLSERIAL SNAPSHOT SOME SOME_EXISTENCE SPLIT SQL
%token <str>   START STATUS STDIN STRICT STRING STORE STORING SUBSTRING
%token <str>   SYMMETRIC SYSTEM

%token <str>   TABLE TABLES TEMP TEMPLATE TEMPORARY TESTING_RANGES TESTING_RELOCATE TEXT THAN THEN
%token <str>   TIME TIMESTAMP TIMESTAMPTZ TO TRAILING TRACE TRANSACTION TREAT TRIM TRUE
%token <str>   TRUNCATE TYPE

%token <str>   UNBOUNDED UNCOMMITTED UNION UNIQUE UNKNOWN
%token <str>   UPDATE UPSERT USE USER USERS USING UUID

%token <str>   VALID VALIDATE VALUE VALUES VARCHAR VARIADIC VIEW VARYING

%token <str>   WHEN WHERE WINDOW WITH WITHIN WITHOUT WRITE

%token <str>   YEAR

%token <str>   ZONE

// The grammar thinks these are keywords, but they are not in any category
// and so can never be entered directly. The filter in scan.go creates these
// tokens when required (based on looking one token ahead).
//
// NOT_LA exists so that productions such as NOT LIKE can be given the same
// precedence as LIKE; otherwise they'd effectively have the same precedence as
// NOT, at least with respect to their left-hand subexpression. WITH_LA is
// needed to make the grammar LALR(1).
%token     NOT_LA WITH_LA AS_LA

%union {
  id             int
  pos            int
  empty          struct{}
  str            string
  union          sqlSymUnion
}

%type <[]Statement> stmt_block
%type <[]Statement> stmt_list
%type <Statement> stmt

%type <Statement> alter_stmt
%type <Statement> alter_ddl_stmt
%type <Statement> alter_table_stmt
%type <Statement> alter_index_stmt
%type <Statement> alter_view_stmt
%type <Statement> alter_database_stmt
%type <Statement> alter_user_stmt
%type <Statement> alter_range_stmt

// ALTER RANGE
%type <Statement> alter_zone_range_stmt

// ALTER TABLE
%type <Statement> alter_onetable_stmt
%type <Statement> alter_split_stmt
%type <Statement> alter_rename_table_stmt
%type <Statement> alter_scatter_stmt
%type <Statement> alter_testing_relocate_stmt
%type <Statement> alter_zone_table_stmt

// ALTER DATABASE
%type <Statement> alter_rename_database_stmt
%type <Statement> alter_zone_database_stmt

// ALTER USER
%type <Statement> alter_user_password_stmt

// ALTER INDEX
%type <Statement> alter_scatter_index_stmt
%type <Statement> alter_split_index_stmt
%type <Statement> alter_rename_index_stmt
%type <Statement> alter_testing_relocate_index_stmt
%type <Statement> alter_zone_index_stmt

// ALTER VIEW
%type <Statement> alter_rename_view_stmt

%type <Statement> backup_stmt
%type <Statement> begin_stmt

%type <Statement> cancel_stmt
%type <Statement> cancel_job_stmt
%type <Statement> cancel_query_stmt

// SCRUB
%type <Statement> scrub_stmt
%type <Statement> scrub_database_stmt
%type <Statement> scrub_table_stmt
%type <ScrubOptions> scrub_option_list
%type <ScrubOption> scrub_option

%type <Statement> commit_stmt
%type <Statement> copy_from_stmt

%type <Statement> create_stmt
%type <Statement> create_ddl_stmt
%type <Statement> create_database_stmt
%type <Statement> create_index_stmt
%type <Statement> create_table_stmt
%type <Statement> create_table_as_stmt
%type <Statement> create_user_stmt
%type <Statement> create_view_stmt
%type <Statement> delete_stmt
%type <Statement> discard_stmt

%type <Statement> drop_stmt
%type <Statement> drop_ddl_stmt
%type <Statement> drop_database_stmt
%type <Statement> drop_index_stmt
%type <Statement> drop_table_stmt
%type <Statement> drop_user_stmt
%type <Statement> drop_view_stmt

%type <Statement> explain_stmt
%type <Statement> prepare_stmt
%type <Statement> preparable_stmt
%type <Statement> explainable_stmt
%type <Statement> execute_stmt
%type <Statement> deallocate_stmt
%type <Statement> grant_stmt
%type <Statement> insert_stmt
%type <Statement> import_stmt
%type <Statement> pause_stmt
%type <Statement> release_stmt
%type <Statement> reset_stmt reset_session_stmt reset_csetting_stmt
%type <Statement> resume_stmt
%type <Statement> restore_stmt
%type <Statement> revoke_stmt
%type <*Select> select_stmt
%type <Statement> rollback_stmt
%type <Statement> savepoint_stmt

%type <Statement> set_stmt
%type <Statement> set_session_stmt
%type <Statement> set_csetting_stmt
%type <Statement> set_transaction_stmt
%type <Statement> set_exprs_internal
%type <Statement> generic_set
%type <Statement> set_rest_more
%type <Statement> set_names

%type <Statement> show_stmt
%type <Statement> show_backup_stmt
%type <Statement> show_columns_stmt
%type <Statement> show_constraints_stmt
%type <Statement> show_create_table_stmt
%type <Statement> show_create_view_stmt
%type <Statement> show_csettings_stmt
%type <Statement> show_databases_stmt
%type <Statement> show_grants_stmt
%type <Statement> show_indexes_stmt
%type <Statement> show_jobs_stmt
%type <Statement> show_queries_stmt
%type <Statement> show_session_stmt
%type <Statement> show_sessions_stmt
%type <Statement> show_tables_stmt
%type <Statement> show_testing_stmt
%type <Statement> show_trace_stmt
%type <Statement> show_transaction_stmt
%type <Statement> show_users_stmt
%type <Statement> show_zone_stmt

%type <str> session_var

%type <Statement> transaction_stmt
%type <Statement> truncate_stmt
%type <Statement> update_stmt
%type <Statement> upsert_stmt
%type <Statement> use_stmt

%type <[]string> opt_incremental
%type <KVOption> kv_option
%type <[]KVOption> kv_option_list opt_with_options
%type <str> import_data_format

%type <*Select> select_no_parens
%type <SelectStatement> select_clause select_with_parens simple_select values_clause table_clause simple_select_clause
%type <SelectStatement> set_operation

%type <empty> alter_using
%type <Expr> alter_column_default
%type <Direction> opt_asc_desc

%type <AlterTableCmd> alter_table_cmd
%type <AlterTableCmds> alter_table_cmds

%type <empty> opt_collate_clause

%type <DropBehavior> opt_drop_behavior
%type <DropBehavior> opt_interleave_drop_behavior

%type <ValidationBehavior> opt_validate_behavior

%type <str> opt_template_clause opt_encoding_clause opt_lc_collate_clause opt_lc_ctype_clause
%type <Expr> opt_password

%type <IsolationLevel> transaction_iso_level
%type <UserPriority>  transaction_user_priority
%type <ReadWriteMode> transaction_read_mode

%type <str>   name opt_name opt_name_parens opt_to_savepoint
%type <str>   savepoint_name

%type <operator> subquery_op
%type <FunctionReference> func_name
%type <empty> opt_collate

%type <UnresolvedName> qualified_name
%type <UnresolvedName> table_pattern
%type <TableExpr> insert_target

%type <*TableNameWithIndex> table_name_with_index
%type <TableNameWithIndexList> table_name_with_index_list

%type <operator> math_op

%type <IsolationLevel> iso_level
%type <UserPriority> user_priority

%type <TableDefs> opt_table_elem_list table_elem_list
%type <*InterleaveDef> opt_interleave
%type <*PartitionBy> opt_partition_by partition_by
%type <str> partition opt_partition
%type <[]ListPartition> list_partitions
%type <[]RangePartition> range_partitions
%type <[]*Tuple> list_partition_values
%type <Exprs> partition_exprs
%type <Expr> partition_expr
%type <empty> opt_all_clause
%type <bool> distinct_clause
%type <NameList> opt_column_list
%type <OrderBy> sort_clause opt_sort_clause
%type <[]*Order> sortby_list
%type <IndexElemList> index_params
%type <NameList> name_list opt_name_list
%type <[]int32> opt_array_bounds
%type <*From> from_clause update_from_clause
%type <TableExprs> from_list
%type <UnresolvedNames> qualified_name_list
%type <TablePatterns> table_pattern_list
%type <UnresolvedName> any_name
%type <TableNameReferences> table_name_list
%type <Exprs> expr_list opt_expr_list
%type <UnresolvedName> attrs
%type <SelectExprs> target_list
%type <UpdateExprs> set_clause_list
%type <*UpdateExpr> set_clause multiple_set_clause
%type <ArraySubscripts> array_subscripts
%type <UnresolvedName> qname_indirection
%type <NamePart> name_indirection_elem
%type <GroupBy> group_clause
%type <*Limit> select_limit opt_select_limit
%type <TableNameReferences> relation_expr_list
%type <ReturningClause> returning_clause

%type <bool> all_or_distinct
%type <empty> join_outer
%type <JoinCond> join_qual
%type <str> join_type

%type <Exprs> extract_list
%type <Exprs> overlay_list
%type <Exprs> position_list
%type <Exprs> substr_list
%type <Exprs> trim_list
%type <Exprs> execute_param_clause
%type <durationField> opt_interval interval_second
%type <Expr> overlay_placing

%type <bool> opt_unique opt_column

%type <empty> opt_set_data

%type <*Limit> limit_clause offset_clause opt_limit_clause
%type <bool> for_locking_clause opt_for_locking_clause
%type <Expr>  select_limit_value
%type <Expr> opt_select_fetch_first_value
%type <empty> row_or_rows
%type <empty> first_or_next

%type <Statement>  insert_rest
%type <NameList> opt_conf_expr
%type <*OnConflict> on_conflict

%type <Statement>  begin_transaction
%type <TransactionModes> transaction_mode_list transaction_mode

%type <NameList> opt_storing
%type <*ColumnTableDef> column_def
%type <TableDef> table_elem
%type <Expr>  where_clause
%type <NamePart> glob_indirection
%type <NamePart> name_indirection
%type <*ArraySubscript> array_subscript
%type <Expr> opt_slice_bound
%type <*IndexHints> opt_index_hints
%type <*IndexHints> index_hints_param
%type <*IndexHints> index_hints_param_list
%type <Expr>  a_expr b_expr c_expr a_expr_const d_expr
%type <Expr>  substr_from substr_for
%type <Expr>  in_expr
%type <Expr>  having_clause
%type <Expr>  array_expr
%type <Expr>  interval
%type <[]coltypes.T> type_list prep_type_clause
%type <Exprs> array_expr_list
%type <Expr>  row explicit_row implicit_row
%type <Expr>  case_expr case_arg case_default
%type <*When>  when_clause
%type <[]*When> when_clause_list
%type <ComparisonOperator> sub_type
%type <Expr> numeric_only
%type <AliasClause> alias_clause opt_alias_clause
%type <bool> opt_ordinality
%type <*Order> sortby
%type <IndexElem> index_elem
%type <TableExpr> table_ref
%type <TableExpr> joined_table
%type <UnresolvedName> relation_expr
%type <TableExpr> relation_expr_opt_alias
%type <SelectExpr> target_elem
%type <*UpdateExpr> single_set_clause
%type <AsOfClause> opt_as_of_clause

%type <str> explain_option_name
%type <[]string> explain_option_list

%type <coltypes.T> typename simple_typename const_typename
%type <coltypes.T> numeric opt_numeric_modifiers
%type <*NumVal> opt_float
%type <coltypes.T> character const_character
%type <coltypes.T> character_with_length character_without_length
%type <coltypes.T> const_datetime const_interval
%type <coltypes.T> bit const_bit bit_with_length bit_without_length
%type <coltypes.T> character_base
%type <coltypes.CastTargetType> postgres_oid
%type <coltypes.CastTargetType> cast_target
%type <str> extract_arg
%type <empty> opt_varying

%type <*NumVal>  signed_iconst
%type <Expr>  var_value
%type <Exprs> var_list
%type <UnresolvedName> var_name
%type <str>   unrestricted_name type_function_name
%type <str>   non_reserved_word
%type <str>   non_reserved_word_or_sconst
%type <Expr>  zone_value
%type <Expr> string_or_placeholder
%type <Expr> string_or_placeholder_list

%type <str>   unreserved_keyword type_func_name_keyword
%type <str>   col_name_keyword reserved_keyword

%type <ConstraintTableDef> table_constraint constraint_elem
%type <TableDef> index_def
%type <TableDef> family_def
%type <[]NamedColumnQualification> col_qual_list
%type <NamedColumnQualification> col_qualification
%type <ColumnQualification> col_qualification_elem
%type <empty> key_match
%type <ReferenceActions> reference_actions
%type <ReferenceAction> reference_action reference_on_delete reference_on_update

%type <Expr>  func_application func_expr_common_subexpr
%type <Expr>  func_expr func_expr_windowless
%type <empty> common_table_expr
%type <empty> with_clause opt_with opt_with_clause
%type <empty> cte_list

%type <empty> within_group_clause
%type <Expr> filter_clause
%type <Exprs> opt_partition_clause
%type <Window> window_clause window_definition_list
%type <*WindowDef> window_definition over_clause window_specification
%type <str> opt_existing_window_name
%type <empty> opt_frame_clause frame_extent frame_bound

%type <[]ColumnID> opt_tableref_col_list tableref_col_list

%type <TargetList>    targets
%type <*TargetList> on_privilege_target_clause
%type <NameList>       grantee_list for_grantee_clause
%type <privilege.List> privileges privilege_list
%type <privilege.Kind> privilege

// Precedence: lowest to highest
%nonassoc  VALUES              // see value_clause
%nonassoc  SET                 // see relation_expr_opt_alias
%left      UNION EXCEPT
%left      INTERSECT
%left      OR
%left      AND
%right     NOT
%nonassoc  IS                  // IS sets precedence for IS NULL, etc
%nonassoc  '<' '>' '=' LESS_EQUALS GREATER_EQUALS NOT_EQUALS CONTAINS CONTAINED_BY '?' SOME_EXISTENCE ALL_EXISTENCE
%nonassoc  '~' BETWEEN IN LIKE ILIKE SIMILAR NOT_REGMATCH REGIMATCH NOT_REGIMATCH NOT_LA
%nonassoc  ESCAPE              // ESCAPE must be just above LIKE/ILIKE/SIMILAR
%nonassoc  OVERLAPS
%left      POSTFIXOP           // dummy for postfix OP rules
// To support target_elem without AS, we must give IDENT an explicit priority
// between POSTFIXOP and OP. We can safely assign the same priority to various
// unreserved keywords as needed to resolve ambiguities (this can't have any
// bad effects since obviously the keywords will still behave the same as if
// they weren't keywords). We need to do this for PARTITION, RANGE, ROWS to
// support opt_existing_window_name; and for RANGE, ROWS so that they can
// follow a_expr without creating postfix-operator problems; and for NULL so
// that it can follow b_expr in col_qual_list without creating postfix-operator
// problems.
//
// To support CUBE and ROLLUP in GROUP BY without reserving them, we give them
// an explicit priority lower than '(', so that a rule with CUBE '(' will shift
// rather than reducing a conflicting rule that takes CUBE as a function name.
// Using the same precedence as IDENT seems right for the reasons given above.
//
// The frame_bound productions UNBOUNDED PRECEDING and UNBOUNDED FOLLOWING are
// even messier: since UNBOUNDED is an unreserved keyword (per spec!), there is
// no principled way to distinguish these from the productions a_expr
// PRECEDING/FOLLOWING. We hack this up by giving UNBOUNDED slightly lower
// precedence than PRECEDING and FOLLOWING. At present this doesn't appear to
// cause UNBOUNDED to be treated differently from other unreserved keywords
// anywhere else in the grammar, but it's definitely risky. We can blame any
// funny behavior of UNBOUNDED on the SQL standard, though.
%nonassoc  UNBOUNDED         // ideally should have same precedence as IDENT
%nonassoc  IDENT NULL PARTITION RANGE ROWS PRECEDING FOLLOWING CUBE ROLLUP
%left      CONCAT FETCHVAL FETCHTEXT FETCHVAL_PATH FETCHTEXT_PATH REMOVE_PATH  // multi-character ops
%left      '|'
%left      '#'
%left      '&'
%left      LSHIFT RSHIFT
%left      '+' '-'
%left      '*' '/' FLOORDIV '%'
%left      '^'
// Unary Operators
%left      AT                // sets precedence for AT TIME ZONE
%left      COLLATE
%right     UMINUS
%left      '[' ']'
%left      '(' ')'
%left      TYPEANNOTATE
%left      TYPECAST
%left      '.'
// These might seem to be low-precedence, but actually they are not part
// of the arithmetic hierarchy at all in their use as JOIN operators.
// We make them high-precedence to support their use as function names.
// They wouldn't be given a precedence at all, were it not that we need
// left-associativity among the JOIN rules themselves.
%left      JOIN CROSS LEFT FULL RIGHT INNER NATURAL
%right     HELPTOKEN

%%

stmt_block:
  stmt_list
  {
    sqllex.(*Scanner).stmts = $1.stmts()
  }

stmt_list:
  stmt_list ';' stmt
  {
    if $3.stmt() != nil {
      $$.val = append($1.stmts(), $3.stmt())
    }
  }
| stmt
  {
    if $1.stmt() != nil {
      $$.val = []Statement{$1.stmt()}
    } else {
      $$.val = []Statement(nil)
    }
  }

stmt:
  HELPTOKEN { return helpWith(sqllex, "") }
| alter_stmt      // help texts in sub-rule
| backup_stmt     // EXTEND WITH HELP: BACKUP
| cancel_stmt     // help texts in sub-rule
| scrub_stmt
| copy_from_stmt
| create_stmt     // help texts in sub-rule
| deallocate_stmt // EXTEND WITH HELP: DEALLOCATE
| delete_stmt     // EXTEND WITH HELP: DELETE
| discard_stmt    // EXTEND WITH HELP: DISCARD
| drop_stmt       // help texts in sub-rule
| execute_stmt    // EXTEND WITH HELP: EXECUTE
| explain_stmt    // EXTEND WITH HELP: EXPLAIN
| grant_stmt      // EXTEND WITH HELP: GRANT
| insert_stmt     // EXTEND WITH HELP: INSERT
| import_stmt     // EXTEND WITH HELP: IMPORT
| pause_stmt      // EXTEND WITH HELP: PAUSE JOB
| prepare_stmt    // EXTEND WITH HELP: PREPARE
| restore_stmt    // EXTEND WITH HELP: RESTORE
| resume_stmt     // EXTEND WITH HELP: RESUME JOB
| revoke_stmt     // EXTEND WITH HELP: REVOKE
| savepoint_stmt  // EXTEND WITH HELP: SAVEPOINT
| select_stmt     // help texts in sub-rule
  {
    $$.val = $1.slct()
  }
| release_stmt     // EXTEND WITH HELP: RELEASE
| reset_stmt       // help texts in sub-rule
| set_stmt         // help texts in sub-rule
| show_stmt        // help texts in sub-rule
| transaction_stmt // help texts in sub-rule
| truncate_stmt    // EXTEND WITH HELP: TRUNCATE
| update_stmt      // EXTEND WITH HELP: UPDATE
| upsert_stmt      // EXTEND WITH HELP: UPSERT
| /* EMPTY */
  {
    $$.val = Statement(nil)
  }

// %Help: ALTER
// %Category: Group
// %Text: ALTER TABLE, ALTER INDEX, ALTER VIEW, ALTER DATABASE, ALTER USER
alter_stmt:
  alter_ddl_stmt      // help texts in sub-rule
| alter_user_stmt     // EXTEND WITH HELP: ALTER USER
| ALTER error         // SHOW HELP: ALTER

alter_ddl_stmt:
  alter_table_stmt    // EXTEND WITH HELP: ALTER TABLE
| alter_index_stmt    // EXTEND WITH HELP: ALTER INDEX
| alter_view_stmt     // EXTEND WITH HELP: ALTER VIEW
| alter_database_stmt // EXTEND WITH HELP: ALTER DATABASE
| alter_range_stmt

// %Help: ALTER TABLE - change the definition of a table
// %Category: DDL
// %Text:
// ALTER TABLE [IF EXISTS] <tablename> <command> [, ...]
//
// Commands:
//   ALTER TABLE ... ADD [COLUMN] [IF NOT EXISTS] <colname> <type> [<qualifiers...>]
//   ALTER TABLE ... ADD <constraint>
//   ALTER TABLE ... DROP [COLUMN] [IF EXISTS] <colname> [RESTRICT | CASCADE]
//   ALTER TABLE ... DROP CONSTRAINT [IF EXISTS] <constraintname> [RESTRICT | CASCADE]
//   ALTER TABLE ... ALTER [COLUMN] <colname> {SET DEFAULT <expr> | DROP DEFAULT}
//   ALTER TABLE ... ALTER [COLUMN] <colname> DROP NOT NULL
//   ALTER TABLE ... RENAME TO <newname>
//   ALTER TABLE ... RENAME [COLUMN] <colname> TO <newname>
//   ALTER TABLE ... VALIDATE CONSTRAINT <constraintname>
//   ALTER TABLE ... SPLIT AT <selectclause>
//   ALTER TABLE ... SCATTER [ FROM ( <exprs...> ) TO ( <exprs...> ) ]
//
// Column qualifiers:
//   [CONSTRAINT <constraintname>] {NULL | NOT NULL | UNIQUE | PRIMARY KEY | CHECK (<expr>) | DEFAULT <expr>}
//   FAMILY <familyname>, CREATE [IF NOT EXISTS] FAMILY [<familyname>]
//   REFERENCES <tablename> [( <colnames...> )]
//   COLLATE <collationname>
//
// %SeeAlso: WEBDOCS/alter-table.html
alter_table_stmt:
  alter_onetable_stmt
| alter_split_stmt
| alter_testing_relocate_stmt
| alter_scatter_stmt
| alter_zone_table_stmt
| alter_rename_table_stmt
// ALTER TABLE has its error help token here because the ALTER TABLE
// prefix is spread over multiple non-terminals.
| ALTER TABLE error // SHOW HELP: ALTER TABLE

// %Help: ALTER VIEW - change the definition of a view
// %Category: DDL
// %Text:
// ALTER VIEW [IF EXISTS] <name> RENAME TO <newname>
// %SeeAlso: WEBDOCS/alter-view.html
alter_view_stmt:
  alter_rename_view_stmt
// ALTER VIEW has its error help token here because the ALTER VIEW
// prefix is spread over multiple non-terminals.
| ALTER VIEW error // SHOW HELP: ALTER VIEW

// %Help: ALTER USER - change user properties
// %Category: Priv
// %Text:
// ALTER USER [IF EXISTS] <name> WITH PASSWORD <password>
// %SeeAlso: CREATE USER
alter_user_stmt:
  alter_user_password_stmt
| ALTER USER error // SHOW HELP: ALTER USER

// %Help: ALTER DATABASE - change the definition of a database
// %Category: DDL
// %Text:
// ALTER DATABASE <name> RENAME TO <newname>
// %SeeAlso: WEBDOCS/alter-database.html
alter_database_stmt:
  alter_rename_database_stmt
|  alter_zone_database_stmt
// ALTER DATABASE has its error help token here because the ALTER DATABASE
// prefix is spread over multiple non-terminals.
| ALTER DATABASE error // SHOW HELP: ALTER DATABASE

alter_range_stmt:
  alter_zone_range_stmt

// %Help: ALTER INDEX - change the definition of an index
// %Category: DDL
// %Text:
// ALTER INDEX [IF EXISTS] <idxname> <command>
//
// Commands:
//   ALTER INDEX ... RENAME TO <newname>
//   ALTER INDEX ... SPLIT AT <selectclause>
//   ALTER INDEX ... SCATTER [ FROM ( <exprs...> ) TO ( <exprs...> ) ]
//
// %SeeAlso: WEBDOCS/alter-index.html
alter_index_stmt:
  alter_split_index_stmt
| alter_testing_relocate_index_stmt
| alter_scatter_index_stmt
| alter_rename_index_stmt
| alter_zone_index_stmt
// ALTER INDEX has its error help token here because the ALTER INDEX
// prefix is spread over multiple non-terminals.
| ALTER INDEX error // SHOW HELP: ALTER INDEX

alter_onetable_stmt:
  ALTER TABLE relation_expr alter_table_cmds
  {
    $$.val = &AlterTable{Table: $3.normalizableTableName(), IfExists: false, Cmds: $4.alterTableCmds()}
  }
| ALTER TABLE IF EXISTS relation_expr alter_table_cmds
  {
    $$.val = &AlterTable{Table: $5.normalizableTableName(), IfExists: true, Cmds: $6.alterTableCmds()}
  }

alter_split_stmt:
  ALTER TABLE qualified_name SPLIT AT select_stmt
  {
    $$.val = &Split{Table: $3.newNormalizableTableName(), Rows: $6.slct()}
  }

alter_split_index_stmt:
  ALTER INDEX table_name_with_index SPLIT AT select_stmt
  {
    $$.val = &Split{Index: $3.newTableWithIdx(), Rows: $6.slct()}
  }

alter_testing_relocate_stmt:
  ALTER TABLE qualified_name TESTING_RELOCATE select_stmt
  {
    /* SKIP DOC */
    $$.val = &TestingRelocate{Table: $3.newNormalizableTableName(), Rows: $5.slct()}
  }

alter_testing_relocate_index_stmt:
  ALTER INDEX table_name_with_index TESTING_RELOCATE select_stmt
  {
    /* SKIP DOC */
    $$.val = &TestingRelocate{Index: $3.newTableWithIdx(), Rows: $5.slct()}
  }

alter_zone_range_stmt:
  ALTER RANGE unrestricted_name EXPERIMENTAL CONFIGURE ZONE a_expr_const
  {
    /* SKIP DOC */
    $$.val = &SetZoneConfig{
      ZoneSpecifier: ZoneSpecifier{NamedZone: UnrestrictedName($3)},
      YAMLConfig: $7.expr(),
    }
  }

alter_zone_database_stmt:
  ALTER DATABASE name EXPERIMENTAL CONFIGURE ZONE a_expr_const
  {
    /* SKIP DOC */
    $$.val = &SetZoneConfig{
      ZoneSpecifier: ZoneSpecifier{Database: Name($3)},
      YAMLConfig: $7.expr(),
    }
  }

alter_zone_table_stmt:
  ALTER TABLE qualified_name opt_partition EXPERIMENTAL CONFIGURE ZONE a_expr_const
  {
    /* SKIP DOC */
    $$.val = &SetZoneConfig{
      ZoneSpecifier: ZoneSpecifier{
        TableOrIndex: TableNameWithIndex{Table: $3.normalizableTableName()},
        Partition: Name($4),
      },
      YAMLConfig: $8.expr(),
    }
  }

alter_zone_index_stmt:
  ALTER INDEX table_name_with_index opt_partition EXPERIMENTAL CONFIGURE ZONE a_expr_const
  {
    /* SKIP DOC */
    $$.val = &SetZoneConfig{
      ZoneSpecifier: ZoneSpecifier{
        TableOrIndex: $3.tableWithIdx(),
        Partition: Name($4),
      },
      YAMLConfig: $8.expr(),
    }
  }

alter_scatter_stmt:
  ALTER TABLE qualified_name SCATTER
  {
    $$.val = &Scatter{Table: $3.newNormalizableTableName()}
  }
| ALTER TABLE qualified_name SCATTER FROM '(' expr_list ')' TO '(' expr_list ')'
  {
    $$.val = &Scatter{Table: $3.newNormalizableTableName(), From: $7.exprs(), To: $11.exprs()}
  }

alter_scatter_index_stmt:
  ALTER INDEX table_name_with_index SCATTER
  {
    $$.val = &Scatter{Index: $3.newTableWithIdx()}
  }
| ALTER INDEX table_name_with_index SCATTER FROM '(' expr_list ')' TO '(' expr_list ')'
  {
    $$.val = &Scatter{Index: $3.newTableWithIdx(), From: $7.exprs(), To: $11.exprs()}
  }

alter_table_cmds:
  alter_table_cmd
  {
    $$.val = AlterTableCmds{$1.alterTableCmd()}
  }
| alter_table_cmds ',' alter_table_cmd
  {
    $$.val = append($1.alterTableCmds(), $3.alterTableCmd())
  }

alter_table_cmd:
  // ALTER TABLE <name> ADD <coldef>
  ADD column_def
  {
    $$.val = &AlterTableAddColumn{columnKeyword: false, IfNotExists: false, ColumnDef: $2.colDef()}
  }
  // ALTER TABLE <name> ADD IF NOT EXISTS <coldef>
| ADD IF NOT EXISTS column_def
  {
    $$.val = &AlterTableAddColumn{columnKeyword: false, IfNotExists: true, ColumnDef: $5.colDef()}
  }
  // ALTER TABLE <name> ADD COLUMN <coldef>
| ADD COLUMN column_def
  {
    $$.val = &AlterTableAddColumn{columnKeyword: true, IfNotExists: false, ColumnDef: $3.colDef()}
  }
  // ALTER TABLE <name> ADD COLUMN IF NOT EXISTS <coldef>
| ADD COLUMN IF NOT EXISTS column_def
  {
    $$.val = &AlterTableAddColumn{columnKeyword: true, IfNotExists: true, ColumnDef: $6.colDef()}
  }
  // ALTER TABLE <name> ALTER [COLUMN] <colname> {SET DEFAULT <expr>|DROP DEFAULT}
| ALTER opt_column name alter_column_default
  {
    $$.val = &AlterTableSetDefault{columnKeyword: $2.bool(), Column: Name($3), Default: $4.expr()}
  }
  // ALTER TABLE <name> ALTER [COLUMN] <colname> DROP NOT NULL
| ALTER opt_column name DROP NOT NULL
  {
    $$.val = &AlterTableDropNotNull{columnKeyword: $2.bool(), Column: Name($3)}
  }
  // ALTER TABLE <name> ALTER [COLUMN] <colname> SET NOT NULL
| ALTER opt_column name SET NOT NULL { return unimplemented(sqllex, "alter set non null") }
  // ALTER TABLE <name> DROP [COLUMN] IF EXISTS <colname> [RESTRICT|CASCADE]
| DROP opt_column IF EXISTS name opt_drop_behavior
  {
    $$.val = &AlterTableDropColumn{
      columnKeyword: $2.bool(),
      IfExists: true,
      Column: Name($5),
      DropBehavior: $6.dropBehavior(),
    }
  }
  // ALTER TABLE <name> DROP [COLUMN] <colname> [RESTRICT|CASCADE]
| DROP opt_column name opt_drop_behavior
  {
    $$.val = &AlterTableDropColumn{
      columnKeyword: $2.bool(),
      IfExists: false,
      Column: Name($3),
      DropBehavior: $4.dropBehavior(),
    }
  }
  // ALTER TABLE <name> ALTER [COLUMN] <colname> [SET DATA] TYPE <typename>
  //     [ USING <expression> ]
| ALTER opt_column name opt_set_data TYPE typename opt_collate_clause alter_using { return unimplemented(sqllex, "alter set type") }
  // ALTER TABLE <name> ADD CONSTRAINT ...
| ADD table_constraint opt_validate_behavior
  {
    $$.val = &AlterTableAddConstraint{
      ConstraintDef: $2.constraintDef(),
      ValidationBehavior: $3.validationBehavior(),
    }
  }
  // ALTER TABLE <name> ALTER CONSTRAINT ...
| ALTER CONSTRAINT name { return unimplemented(sqllex, "alter constraint") }
  // ALTER TABLE <name> VALIDATE CONSTRAINT ...
| VALIDATE CONSTRAINT name
  {
    $$.val = &AlterTableValidateConstraint{
      Constraint: Name($3),
    }
  }
  // ALTER TABLE <name> DROP CONSTRAINT IF EXISTS <name> [RESTRICT|CASCADE]
| DROP CONSTRAINT IF EXISTS name opt_drop_behavior
  {
    $$.val = &AlterTableDropConstraint{
      IfExists: true,
      Constraint: Name($5),
      DropBehavior: $6.dropBehavior(),
    }
  }
  // ALTER TABLE <name> DROP CONSTRAINT <name> [RESTRICT|CASCADE]
| DROP CONSTRAINT name opt_drop_behavior
  {
    $$.val = &AlterTableDropConstraint{
      IfExists: false,
      Constraint: Name($3),
      DropBehavior: $4.dropBehavior(),
    }
  }

alter_column_default:
  SET DEFAULT a_expr
  {
    $$.val = $3.expr()
  }
| DROP DEFAULT
  {
    $$.val = nil
  }

opt_drop_behavior:
  CASCADE
  {
    $$.val = DropCascade
  }
| RESTRICT
  {
    $$.val = DropRestrict
  }
| /* EMPTY */
  {
    $$.val = DropDefault
  }

opt_validate_behavior:
  NOT VALID
  {
    $$.val = ValidationSkip
  }
| /* EMPTY */
  {
    $$.val = ValidationDefault
  }

opt_collate_clause:
  COLLATE unrestricted_name { return unimplementedWithIssue(sqllex, 9851) }
| /* EMPTY */ {}

alter_using:
  USING a_expr { return unimplemented(sqllex, "alter using") }
| /* EMPTY */ {}

// %Help: BACKUP - back up data to external storage
// %Category: CCL
// %Text:
// BACKUP <targets...> TO <location...>
//        [ AS OF SYSTEM TIME <expr> ]
//        [ INCREMENTAL FROM <location...> ]
//        [ WITH <option> [= <value>] [, ...] ]
//
// Targets:
//    TABLE <pattern> [, ...]
//    DATABASE <databasename> [, ...]
//
// Location:
//    "[scheme]://[host]/[path to backup]?[parameters]"
//
// Options:
//    INTO_DB
//    SKIP_MISSING_FOREIGN_KEYS
//
// %SeeAlso: RESTORE, WEBDOCS/backup.html
backup_stmt:
  BACKUP targets TO string_or_placeholder opt_as_of_clause opt_incremental opt_with_options
  {
    $$.val = &Backup{Targets: $2.targetList(), To: $4.expr(), IncrementalFrom: $6.exprs(), AsOf: $5.asOfClause(), Options: $7.kvOptions()}
  }
| BACKUP error // SHOW HELP: BACKUP

// %Help: RESTORE - restore data from external storage
// %Category: CCL
// %Text:
// RESTORE <targets...> FROM <location...>
//         [ AS OF SYSTEM TIME <expr> ]
//         [ WITH <option> [= <value>] [, ...] ]
//
// Targets:
//    TABLE <pattern> [, ...]
//    DATABASE <databasename> [, ...]
//
// Locations:
//    "[scheme]://[host]/[path to backup]?[parameters]"
//
// Options:
//    INTO_DB
//    SKIP_MISSING_FOREIGN_KEYS
//
// %SeeAlso: BACKUP, WEBDOCS/restore.html
restore_stmt:
  RESTORE targets FROM string_or_placeholder_list opt_as_of_clause opt_with_options
  {
    $$.val = &Restore{Targets: $2.targetList(), From: $4.exprs(), AsOf: $5.asOfClause(), Options: $6.kvOptions()}
  }
| RESTORE error // SHOW HELP: RESTORE

import_data_format:
  CSV
  {
    $$ = "CSV"
  }

// %Help: IMPORT - load data from file in a distributed manner
// %Category: CCL
// %Text:
// IMPORT TABLE <tablename>
//        { ( <elements> ) | CREATE USING <schemafile> }
//        <format>
//        DATA ( <datafile> [, ...] )
//        [ WITH <option> [= <value>] [, ...] ]
//
// Formats:
//    CSV
//
// Options:
//    distributed = '...'
//    sstsize = '...'
//    temp = '...'
//    comma = '...'          [CSV-specific]
//    comment = '...'        [CSV-specific]
//    nullif = '...'         [CSV-specific]
//
// %SeeAlso: CREATE TABLE
import_stmt:
  IMPORT TABLE any_name CREATE USING string_or_placeholder import_data_format DATA '(' string_or_placeholder_list ')' opt_with_options
  {
    $$.val = &Import{Table: $3.unresolvedName(), CreateFile: $6.expr(), FileFormat: $7, Files: $10.exprs(), Options: $12.kvOptions()}
  }
| IMPORT TABLE any_name '(' table_elem_list ')' import_data_format DATA '(' string_or_placeholder_list ')' opt_with_options
  {
    $$.val = &Import{Table: $3.unresolvedName(), CreateDefs: $5.tblDefs(), FileFormat: $7, Files: $10.exprs(), Options: $12.kvOptions()}
  }
| IMPORT error // SHOW HELP: IMPORT

string_or_placeholder:
  non_reserved_word_or_sconst
  {
    $$.val = &StrVal{s: $1}
  }
| PLACEHOLDER
  {
    $$.val = NewPlaceholder($1)
  }

string_or_placeholder_list:
  string_or_placeholder
  {
    $$.val = Exprs{$1.expr()}
  }
| string_or_placeholder_list ',' string_or_placeholder
  {
    $$.val = append($1.exprs(), $3.expr())
  }

opt_incremental:
  INCREMENTAL FROM string_or_placeholder_list
  {
    $$.val = $3.exprs()
  }
| /* EMPTY */
  {
    $$.val = Exprs(nil)
  }

kv_option:
  name '=' string_or_placeholder
  {
    $$.val = KVOption{Key: Name($1), Value: $3.expr()}
  }
|  name
  {
    $$.val = KVOption{Key: Name($1)}
  }
|  SCONST '=' string_or_placeholder
  {
    $$.val = KVOption{Key: Name($1), Value: $3.expr()}
  }
|  SCONST
  {
    $$.val = KVOption{Key: Name($1)}
  }

kv_option_list:
  kv_option
  {
    $$.val = []KVOption{$1.kvOption()}
  }
|  kv_option_list ',' kv_option
  {
    $$.val = append($1.kvOptions(), $3.kvOption())
  }

opt_with_options:
  WITH kv_option_list
  {
    $$.val = $2.kvOptions()
  }
| WITH OPTIONS '(' kv_option_list ')'
  {
    $$.val = $4.kvOptions()
  }
| /* EMPTY */ {}

copy_from_stmt:
  COPY qualified_name FROM STDIN
  {
    $$.val = &CopyFrom{Table: $2.normalizableTableName(), Stdin: true}
  }
| COPY qualified_name '(' ')' FROM STDIN
  {
    $$.val = &CopyFrom{Table: $2.normalizableTableName(), Stdin: true}
  }
| COPY qualified_name '(' qualified_name_list ')' FROM STDIN
  {
    $$.val = &CopyFrom{Table: $2.normalizableTableName(), Columns: $4.unresolvedNames(), Stdin: true}
  }

// %Help: CANCEL
// %Category: Group
// %Text: CANCEL JOB, CANCEL QUERY
cancel_stmt:
  cancel_job_stmt   // EXTEND WITH HELP: CANCEL JOB
| cancel_query_stmt // EXTEND WITH HELP: CANCEL QUERY
| CANCEL error      // SHOW HELP: CANCEL

// %Help: CANCEL JOB - cancel a background job
// %Category: Misc
// %Text: CANCEL JOB <jobid>
// %SeeAlso: SHOW JOBS, PAUSE JOBS, RESUME JOB
cancel_job_stmt:
  CANCEL JOB a_expr
  {
    $$.val = &CancelJob{ID: $3.expr()}
  }
| CANCEL JOB error // SHOW HELP: CANCEL JOB

// %Help: CANCEL QUERY - cancel a running query
// %Category: Misc
// %Text: CANCEL QUERY <queryid>
// %SeeAlso: SHOW QUERIES
cancel_query_stmt:
  CANCEL QUERY a_expr
  {
    $$.val = &CancelQuery{ID: $3.expr()}
  }
| CANCEL QUERY error // SHOW HELP: CANCEL QUERY

// %Help: CREATE
// %Category: Group
// %Text:
// CREATE DATABASE, CREATE TABLE, CREATE INDEX, CREATE TABLE AS,
// CREATE USER, CREATE VIEW
create_stmt:
  create_user_stmt     // EXTEND WITH HELP: CREATE USER
| create_ddl_stmt      // help texts in sub-rule
| CREATE error         // SHOW HELP: CREATE

create_ddl_stmt:
  create_database_stmt // EXTEND WITH HELP: CREATE DATABASE
| create_index_stmt    // EXTEND WITH HELP: CREATE INDEX
| create_table_stmt    // EXTEND WITH HELP: CREATE TABLE
| create_table_as_stmt // EXTEND WITH HELP: CREATE TABLE
// Error case for both CREATE TABLE and CREATE TABLE ... AS in one
| CREATE TABLE error   // SHOW HELP: CREATE TABLE
| create_view_stmt     // EXTEND WITH HELP: CREATE VIEW


// %Help: DELETE - delete rows from a table
// %Category: DML
// %Text: DELETE FROM <tablename> [WHERE <expr>]
//               [LIMIT <expr>]
//               [RETURNING <exprs...>]
// %SeeAlso: WEBDOCS/delete.html
delete_stmt:
  opt_with_clause DELETE FROM relation_expr_opt_alias where_clause opt_limit_clause returning_clause
  {
    $$.val = &Delete{
      Table: $4.tblExpr(),
      Where: newWhere(astWhere, $5.expr()),
      Limit: $6.limit(),
      Returning: $7.retClause(),
    }
  }
| opt_with_clause DELETE error // SHOW HELP: DELETE

// %Help: DISCARD - reset the session to its initial state
// %Category: Cfg
// %Text: DISCARD ALL
discard_stmt:
  DISCARD ALL
  {
    $$.val = &Discard{Mode: DiscardModeAll}
  }
| DISCARD PLANS { return unimplemented(sqllex, "discard plans") }
| DISCARD SEQUENCES { return unimplemented(sqllex, "discard sequences") }
| DISCARD TEMP { return unimplemented(sqllex, "discard temp") }
| DISCARD TEMPORARY { return unimplemented(sqllex, "discard temporary") }
| DISCARD error // SHOW HELP: DISCARD

// %Help: DROP
// %Category: Group
// %Text: DROP DATABASE, DROP INDEX, DROP TABLE, DROP VIEW, DROP USER
drop_stmt:
  drop_ddl_stmt      // help texts in sub-rule
| drop_user_stmt     // EXTEND WITH HELP: DROP USER
| DROP error         // SHOW HELP: DROP

drop_ddl_stmt:
  drop_database_stmt // EXTEND WITH HELP: DROP DATABASE
| drop_index_stmt    // EXTEND WITH HELP: DROP INDEX
| drop_table_stmt    // EXTEND WITH HELP: DROP TABLE
| drop_view_stmt     // EXTEND WITH HELP: DROP VIEW

// %Help: DROP VIEW - remove a view
// %Category: DDL
// %Text: DROP VIEW [IF EXISTS] <tablename> [, ...] [CASCADE | RESTRICT]
// %SeeAlso: WEBDOCS/drop-index.html
drop_view_stmt:
  DROP VIEW table_name_list opt_drop_behavior
  {
    $$.val = &DropView{Names: $3.tableNameReferences(), IfExists: false, DropBehavior: $4.dropBehavior()}
  }
| DROP VIEW IF EXISTS table_name_list opt_drop_behavior
  {
    $$.val = &DropView{Names: $5.tableNameReferences(), IfExists: true, DropBehavior: $6.dropBehavior()}
  }
| DROP VIEW error // SHOW HELP: DROP VIEW

// %Help: DROP TABLE - remove a table
// %Category: DDL
// %Text: DROP TABLE [IF EXISTS] <tablename> [, ...] [CASCADE | RESTRICT]
// %SeeAlso: WEBDOCS/drop-table.html
drop_table_stmt:
  DROP TABLE table_name_list opt_drop_behavior
  {
    $$.val = &DropTable{Names: $3.tableNameReferences(), IfExists: false, DropBehavior: $4.dropBehavior()}
  }
| DROP TABLE IF EXISTS table_name_list opt_drop_behavior
  {
    $$.val = &DropTable{Names: $5.tableNameReferences(), IfExists: true, DropBehavior: $6.dropBehavior()}
  }
| DROP TABLE error // SHOW HELP: DROP TABLE

// %Help: DROP INDEX - remove an index
// %Category: DDL
// %Text: DROP INDEX [IF EXISTS] <idxname> [, ...] [CASCADE | RESTRICT]
// %SeeAlso: WEBDOCS/drop-index.html
drop_index_stmt:
  DROP INDEX table_name_with_index_list opt_drop_behavior
  {
    $$.val = &DropIndex{
      IndexList: $3.newTableWithIdxList(),
      IfExists: false,
      DropBehavior: $4.dropBehavior(),
    }
  }
| DROP INDEX IF EXISTS table_name_with_index_list opt_drop_behavior
  {
    $$.val = &DropIndex{
      IndexList: $5.newTableWithIdxList(),
      IfExists: true,
      DropBehavior: $6.dropBehavior(),
    }
  }
| DROP INDEX error // SHOW HELP: DROP INDEX

// %Help: DROP DATABASE - remove a database
// %Category: DDL
// %Text: DROP DATABASE [IF EXISTS] <databasename> [CASCADE | RESTRICT]
// %SeeAlso: WEBDOCS/drop-database.html
drop_database_stmt:
  DROP DATABASE name opt_drop_behavior
  {
    $$.val = &DropDatabase{
      Name: Name($3),
      IfExists: false,
      DropBehavior: $4.dropBehavior(),
    }
  }
| DROP DATABASE IF EXISTS name opt_drop_behavior
  {
    $$.val = &DropDatabase{
      Name: Name($5),
      IfExists: true,
      DropBehavior: $6.dropBehavior(),
    }
  }
| DROP DATABASE error // SHOW HELP: DROP DATABASE

// %Help: DROP USER - remove a user
// %Category: Priv
// %Text: DROP USER [IF EXISTS] <user> [, ...]
// %SeeAlso: CREATE USER, SHOW USERS
drop_user_stmt:
  DROP USER string_or_placeholder_list
  {
    $$.val = &DropUser{Names: $3.exprs(), IfExists: false}
  }
| DROP USER IF EXISTS string_or_placeholder_list
  {
    $$.val = &DropUser{Names: $5.exprs(), IfExists: true}
  }
| DROP USER error // SHOW HELP: DROP USER

table_name_list:
  any_name
  {
    $$.val = TableNameReferences{$1.unresolvedName()}
  }
| table_name_list ',' any_name
  {
    $$.val = append($1.tableNameReferences(), $3.unresolvedName())
  }

any_name:
  name
  {
    $$.val = UnresolvedName{Name($1)}
  }
| name attrs
  {
    $$.val = append(UnresolvedName{Name($1)}, $2.unresolvedName()...)
  }

attrs:
  '.' unrestricted_name
  {
    $$.val = UnresolvedName{Name($2)}
  }
| attrs '.' unrestricted_name
  {
    $$.val = append($1.unresolvedName(), Name($3))
  }

// %Help: EXPLAIN - show the logical plan of a query
// %Category: Misc
// %Text:
// EXPLAIN <statement>
// EXPLAIN [( [PLAN ,] <planoptions...> )] <statement>
//
// Explainable statements:
//     SELECT, CREATE, DROP, ALTER, INSERT, UPSERT, UPDATE, DELETE,
//     SHOW, EXPLAIN, EXECUTE
//
// Plan options:
//     TYPES, EXPRS, METADATA, QUALIFY, INDENT, VERBOSE, DIST_SQL
//
// %SeeAlso: WEBDOCS/explain.html
explain_stmt:
  EXPLAIN explainable_stmt
  {
    $$.val = &Explain{Statement: $2.stmt()}
  }
| EXPLAIN error // SHOW HELP: EXPLAIN
| EXPLAIN '(' explain_option_list ')' explainable_stmt
  {
    $$.val = &Explain{Options: $3.strs(), Statement: $5.stmt()}
  }
// This second error rule is necessary, because otherwise
// explainable_stmt also provides "selectclause := '(' error ..."  and
// cause a help text for the select clause, which will be confusing in
// the context of EXPLAIN.
| EXPLAIN '(' error // SHOW HELP: EXPLAIN

preparable_stmt:
  alter_user_stmt   // EXTEND WITH HELP: ALTER USER
| backup_stmt       // EXTEND WITH HELP: BACKUP
| cancel_stmt       // help texts in sub-rule
| create_user_stmt  // EXTEND WITH HELP: CREATE USER
| delete_stmt       // EXTEND WITH HELP: DELETE
| drop_user_stmt    // EXTEND WITH HELP: DROP USER
| import_stmt       // EXTEND WITH HELP: IMPORT
| insert_stmt       // EXTEND WITH HELP: INSERT
| pause_stmt        // EXTEND WITH HELP: PAUSE JOB
| reset_stmt        // help texts in sub-rule
| restore_stmt      // EXTEND WITH HELP: RESTORE
| resume_stmt       // EXTEND WITH HELP: RESUME JOB
| select_stmt       // help texts in sub-rule
  {
    $$.val = $1.slct()
  }
| set_session_stmt  // EXTEND WITH HELP: SET SESSION
| set_csetting_stmt // EXTEND WITH HELP: SET CLUSTER SETTING
| show_stmt         // help texts in sub-rule
| update_stmt       // EXTEND WITH HELP: UPDATE
| upsert_stmt       // EXTEND WITH HELP: UPSERT

explainable_stmt:
  preparable_stmt
| alter_ddl_stmt   // help texts in sub-rule
| create_ddl_stmt  // help texts in sub-rule
| drop_ddl_stmt    // help texts in sub-rule
| execute_stmt     // EXTEND WITH HELP: EXECUTE
| explain_stmt { /* SKIP DOC */ }

explain_option_list:
  explain_option_name
  {
    $$.val = []string{$1}
  }
| explain_option_list ',' explain_option_name
  {
    $$.val = append($1.strs(), $3)
  }

explain_option_name:
  non_reserved_word

// %Help: PREPARE - prepare a statement for later execution
// %Category: Misc
// %Text: PREPARE <name> [ ( <types...> ) ] AS <query>
// %SeeAlso: EXECUTE, DEALLOCATE, DISCARD
prepare_stmt:
  PREPARE name prep_type_clause AS preparable_stmt
  {
    $$.val = &Prepare{
      Name: Name($2),
      Types: $3.colTypes(),
      Statement: $5.stmt(),
    }
  }
| PREPARE error // SHOW HELP: PREPARE

prep_type_clause:
  '(' type_list ')'
  {
    $$.val = $2.colTypes();
  }
| /* EMPTY */
  {
    $$.val = []coltypes.T(nil)
  }

// %Help: EXECUTE - execute a statement prepared previously
// %Category: Misc
// %Text: EXECUTE <name> [ ( <exprs...> ) ]
// %SeeAlso: PREPARE, DEALLOCATE, DISCARD
execute_stmt:
  EXECUTE name execute_param_clause
  {
    $$.val = &Execute{
      Name: Name($2),
      Params: $3.exprs(),
    }
  }
| EXECUTE error // SHOW HELP: EXECUTE
//   CREATE TABLE <name> AS EXECUTE <plan_name> [(params, ...)]
// | CREATE opt_temp TABLE create_as_target AS EXECUTE name execute_param_clause opt_with_data { return unimplemented(sqllex) }

execute_param_clause:
  '(' expr_list ')'
  {
    $$.val = $2.exprs()
  }
| /* EMPTY */
  {
    $$.val = Exprs(nil)
  }

// %Help: DEALLOCATE - remove a prepared statement
// %Category: Misc
// %Text: DEALLOCATE [PREPARE] { <name> | ALL }
// %SeeAlso: PREPARE, EXECUTE, DISCARD
deallocate_stmt:
  DEALLOCATE name
  {
    $$.val = &Deallocate{Name: Name($2)}
  }
| DEALLOCATE PREPARE name
  {
    $$.val = &Deallocate{Name: Name($3)}
  }
| DEALLOCATE ALL
  {
    $$.val = &Deallocate{}
  }
| DEALLOCATE PREPARE ALL
  {
    $$.val = &Deallocate{}
  }
| DEALLOCATE error // SHOW HELP: DEALLOCATE

// %Help: GRANT - define access privileges
// %Category: Priv
// %Text:
// GRANT {ALL | <privileges...> } ON <targets...> TO <grantees...>
//
// Privileges:
//   CREATE, DROP, GRANT, SELECT, INSERT, DELETE, UPDATE
//
// Targets:
//   DATABASE <databasename> [, ...]
//   [TABLE] [<databasename> .] { <tablename> | * } [, ...]
//
// %SeeAlso: REVOKE, WEBDOCS/grant.html
grant_stmt:
  GRANT privileges ON targets TO grantee_list
  {
    $$.val = &Grant{Privileges: $2.privilegeList(), Grantees: $6.nameList(), Targets: $4.targetList()}
  }
| GRANT error // SHOW HELP: GRANT

// %Help: REVOKE - remove access privileges
// %Category: Priv
// %Text:
// REVOKE {ALL | <privileges...> } ON <targets...> FROM <grantees...>
//
// Privileges:
//   CREATE, DROP, GRANT, SELECT, INSERT, DELETE, UPDATE
//
// Targets:
//   DATABASE <databasename> [, <databasename>]...
//   [TABLE] [<databasename> .] { <tablename> | * } [, ...]
//
// %SeeAlso: GRANT, WEBDOCS/revoke.html
revoke_stmt:
  REVOKE privileges ON targets FROM grantee_list
  {
    $$.val = &Revoke{Privileges: $2.privilegeList(), Grantees: $6.nameList(), Targets: $4.targetList()}
  }
| REVOKE error // SHOW HELP: REVOKE

targets:
  table_pattern_list
  {
    $$.val = TargetList{Tables: $1.tablePatterns()}
  }
| TABLE table_pattern_list
  {
    $$.val = TargetList{Tables: $2.tablePatterns()}
  }
|  DATABASE name_list
  {
    $$.val = TargetList{Databases: $2.nameList()}
  }

// ALL is always by itself.
privileges:
  ALL
  {
    $$.val = privilege.List{privilege.ALL}
  }
  | privilege_list { }

privilege_list:
  privilege
  {
    $$.val = privilege.List{$1.privilegeType()}
  }
  | privilege_list ',' privilege
  {
    $$.val = append($1.privilegeList(), $3.privilegeType())
  }

// This list must match the list of privileges in sql/privilege/privilege.go.
privilege:
  CREATE
  {
    $$.val = privilege.CREATE
  }
| DROP
  {
    $$.val = privilege.DROP
  }
| GRANT
  {
    $$.val = privilege.GRANT
  }
| SELECT
  {
    $$.val = privilege.SELECT
  }
| INSERT
  {
    $$.val = privilege.INSERT
  }
| DELETE
  {
    $$.val = privilege.DELETE
  }
| UPDATE
  {
    $$.val = privilege.UPDATE
  }

// TODO(marc): this should not be 'name', but should instead be a
// type just for usernames.
grantee_list:
  name
  {
    $$.val = NameList{Name($1)}
  }
| grantee_list ',' name
  {
    $$.val = append($1.nameList(), Name($3))
  }

reset_stmt:
  reset_session_stmt  // EXTEND WITH HELP: RESET
| reset_csetting_stmt // EXTEND WITH HELP: RESET CLUSTER SETTING

// %Help: RESET - reset a session variable to its default value
// %Category: Cfg
// %Text: RESET [SESSION] <var>
// %SeeAlso: RESET CLUSTER SETTING, WEBDOCS/set-vars.html
reset_session_stmt:
  RESET session_var
  {
    $$.val = &SetVar{Name: UnresolvedName{Name($2)}, Values:Exprs{DefaultVal{}}}
  }
| RESET SESSION session_var
  {
    $$.val = &SetVar{Name: UnresolvedName{Name($3)}, Values:Exprs{DefaultVal{}}}
  }
| RESET error // SHOW HELP: RESET

// %Help: RESET CLUSTER SETTING - reset a cluster setting to its default value
// %Category: Cfg
// %Text: RESET CLUSTER SETTING <var>
// %SeeAlso: SET CLUSTER SETTING, RESET
reset_csetting_stmt:
  RESET CLUSTER SETTING var_name
  {
    $$.val = &SetClusterSetting{Name: $4.unresolvedName(), Value:DefaultVal{}}
  }
| RESET CLUSTER error // SHOW HELP: RESET CLUSTER SETTING

// USE is the MSSQL/MySQL equivalent of SET DATABASE. Alias it for convenience.
use_stmt:
  USE var_value
  {
    /* SKIP DOC */
    $$.val = &SetVar{Name: UnresolvedName{Name("database")}, Values: Exprs{$2.expr()}}
  }
| USE error // SHOW HELP: SET SESSION

// SET SESSION / SET CLUSTER SETTING / SET TRANSACTION
set_stmt:
  set_session_stmt     // EXTEND WITH HELP: SET SESSION
| set_csetting_stmt    // EXTEND WITH HELP: SET CLUSTER SETTING
| set_transaction_stmt // EXTEND WITH HELP: SET TRANSACTION
| set_exprs_internal   { /* SKIP DOC */ }
| use_stmt             { /* SKIP DOC */ }
| SET LOCAL error { return unimplemented(sqllex, "set local") }

// SCRUB
scrub_stmt:
  scrub_table_stmt
| scrub_database_stmt

// %Help: SCRUB DATABASE - run a scrub check on a database
// %Category: Misc
// %Text:
// SCRUB DATABASE <databasename>
scrub_database_stmt:
  EXPERIMENTAL SCRUB DATABASE name
  {
    $$.val = &Scrub{Typ: ScrubDatabase, Database: Name($4)}
  }

// %Help: SCRUB TABLE - run a scrub check on a table
// %Category: Misc
// %Text:
// SCRUB TABLE <tablename> [WITH <option> [, ...]]
//
// Options:
//   SCRUB TABLE ... WITH OPTIONS INDEX ALL
//   SCRUB TABLE ... WITH OPTIONS INDEX (<index>...)
//   SCRUB TABLE ... WITH OPTIONS PHYSICAL
//
scrub_table_stmt:
  EXPERIMENTAL SCRUB TABLE qualified_name
  {
    $$.val = &Scrub{Typ: ScrubTable, Table: $4.normalizableTableName()}
  }
| EXPERIMENTAL SCRUB TABLE qualified_name WITH OPTIONS scrub_option_list
  {
    $$.val = &Scrub{Typ: ScrubTable, Table: $4.normalizableTableName(), Options: $7.scrubOptions()}
  }

scrub_option_list:
  scrub_option
  {
    $$.val = ScrubOptions{$1.scrubOption()}
  }
| scrub_option_list ',' scrub_option
  {
    $$.val = append($1.scrubOptions(), $3.scrubOption())
  }

scrub_option:
  INDEX ALL
  {
    $$.val = &ScrubOptionIndex{}
  }
| INDEX '(' name_list ')'
  {
    $$.val = &ScrubOptionIndex{IndexNames: $3.nameList()}
  }
| PHYSICAL
  {
    $$.val = &ScrubOptionPhysical{}
  }

// %Help: SET CLUSTER SETTING - change a cluster setting
// %Category: Cfg
// %Text: SET CLUSTER SETTING <var> { TO | = } <value>
// %SeeAlso: SHOW CLUSTER SETTING, RESET CLUSTER SETTING, SET SESSION,
// WEBDOCS/cluster-settings.html
set_csetting_stmt:
  SET CLUSTER SETTING var_name '=' var_value
  {
    $$.val = &SetClusterSetting{Name: $4.unresolvedName(), Value: $6.expr()}
  }
| SET CLUSTER SETTING var_name TO var_value
  {
    $$.val = &SetClusterSetting{Name: $4.unresolvedName(), Value: $6.expr()}
  }
| SET CLUSTER error // SHOW HELP: SET CLUSTER SETTING

set_exprs_internal:
  /* SET ROW serves to accelerate parser.parseExprs().
     It cannot be used by clients. */
  SET ROW '(' expr_list ')'
  {
    $$.val = &SetVar{Values: $4.exprs()}
  }

// %Help: SET SESSION - change a session variable
// %Category: Cfg
// %Text:
// SET [SESSION] <var> { TO | = } <values...>
// SET [SESSION] TIME ZONE <tz>
// SET [SESSION] CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL { SNAPSHOT | SERIALIZABLE }
//
// %SeeAlso: SHOW SESSION, RESET, DISCARD, SHOW, SET CLUSTER SETTING, SET TRANSACTION,
// WEBDOCS/set-vars.html
set_session_stmt:
  SET SESSION set_rest_more
  {
    $$.val = $3.stmt()
  }
| SET set_rest_more
  {
    $$.val = $2.stmt()
  }
// Special form for pg compatibility:
| SET SESSION CHARACTERISTICS AS TRANSACTION transaction_iso_level
  {
    $$.val = &SetDefaultIsolation{Isolation: $6.isoLevel()}
  }

// %Help: SET TRANSACTION - configure the transaction settings
// %Category: Txn
// %Text:
// SET [SESSION] TRANSACTION <txnparameters...>
//
// Transaction parameters:
//    ISOLATION LEVEL { SNAPSHOT | SERIALIZABLE }
//    PRIORITY { LOW | NORMAL | HIGH }
//
// %SeeAlso: SHOW TRANSACTION, SET SESSION,
// WEBDOCS/set-transaction.html
set_transaction_stmt:
  SET TRANSACTION transaction_mode_list
  {
    $$.val = &SetTransaction{Modes: $3.transactionModes()}
  }
| SET TRANSACTION error // SHOW HELP: SET TRANSACTION
| SET SESSION TRANSACTION transaction_mode_list
  {
    $$.val = &SetTransaction{Modes: $4.transactionModes()}
  }
| SET SESSION TRANSACTION error // SHOW HELP: SET TRANSACTION

generic_set:
  var_name TO var_list
  {
    $$.val = &SetVar{Name: $1.unresolvedName(), Values: $3.exprs()}
  }
| var_name '=' var_list
  {
    $$.val = &SetVar{Name: $1.unresolvedName(), Values: $3.exprs()}
  }

set_rest_more:
// Generic SET syntaxes:
   generic_set
// Special syntaxes mandated by SQL standard:
| TIME ZONE zone_value
  {
    /* SKIP DOC */
    $$.val = &SetVar{Name: UnresolvedName{Name("time zone")}, Values: Exprs{$3.expr()}}
  }
| var_name FROM CURRENT { return unimplemented(sqllex, "set from current") }
| set_names
| error // SHOW HELP: SET SESSION

// SET NAMES is the SQL standard syntax for SET client_encoding.
// See https://www.postgresql.org/docs/9.6/static/multibyte.html#AEN39236
set_names:
  NAMES var_value
  {
    /* SKIP DOC */
    $$.val = &SetVar{Name: UnresolvedName{Name("client_encoding")}, Values: Exprs{$2.expr()}}
  }
| NAMES
  {
    /* SKIP DOC */
    $$.val = &SetVar{Name: UnresolvedName{Name("client_encoding")}, Values: Exprs{DefaultVal{}}}
  }

var_name:
  any_name

var_value:
  a_expr
| ON
  {
    $$.val = UnresolvedName{Name($1)}
  }

var_list:
  var_value
  {
    $$.val = Exprs{$1.expr()}
  }
| var_list ',' var_value
  {
    $$.val = append($1.exprs(), $3.expr())
  }

iso_level:
  READ UNCOMMITTED
  {
    $$.val = SnapshotIsolation
  }
| READ COMMITTED
  {
    $$.val = SnapshotIsolation
  }
| SNAPSHOT
  {
    $$.val = SnapshotIsolation
  }
| REPEATABLE READ
  {
    $$.val = SerializableIsolation
  }
| SERIALIZABLE
  {
    $$.val = SerializableIsolation
  }

user_priority:
  LOW
  {
    $$.val = Low
  }
| NORMAL
  {
    $$.val = Normal
  }
| HIGH
  {
    $$.val = High
  }

// Timezone values can be:
// - a string such as 'pst8pdt'
// - an identifier such as "pst8pdt"
// - an integer or floating point number
// - a time interval per SQL99
zone_value:
  SCONST
  {
    $$.val = &StrVal{s: $1}
  }
| IDENT
  {
    $$.val = &StrVal{s: $1}
  }
| interval
  {
    $$.val = $1.expr()
  }
| numeric_only
| DEFAULT
  {
    $$.val = DefaultVal{}
  }
| LOCAL
  {
    $$.val = &StrVal{s: $1}
  }

non_reserved_word_or_sconst:
  non_reserved_word
| SCONST

// %Help: SHOW
// %Category: Group
// %Text:
// SHOW SESSION, SHOW CLUSTER SETTING, SHOW DATABASES, SHOW TABLES, SHOW COLUMNS, SHOW INDEXES,
// SHOW CONSTRAINTS, SHOW CREATE TABLE, SHOW CREATE VIEW, SHOW USERS, SHOW TRANSACTION, SHOW BACKUP,
// SHOW JOBS, SHOW QUERIES, SHOW SESSIONS, SHOW TRACE
show_stmt:
  show_backup_stmt       // EXTEND WITH HELP: SHOW BACKUP
| show_columns_stmt      // EXTEND WITH HELP: SHOW COLUMNS
| show_constraints_stmt  // EXTEND WITH HELP: SHOW CONSTRAINTS
| show_create_table_stmt // EXTEND WITH HELP: SHOW CREATE TABLE
| show_create_view_stmt  // EXTEND WITH HELP: SHOW CREATE VIEW
| show_csettings_stmt    // EXTEND WITH HELP: SHOW CLUSTER SETTING
| show_databases_stmt    // EXTEND WITH HELP: SHOW DATABASES
| show_grants_stmt       // EXTEND WITH HELP: SHOW GRANTS
| show_indexes_stmt      // EXTEND WITH HELP: SHOW INDEXES
| show_jobs_stmt         // EXTEND WITH HELP: SHOW JOBS
| show_queries_stmt      // EXTEND WITH HELP: SHOW QUERIES
| show_session_stmt      // EXTEND WITH HELP: SHOW SESSION
| show_sessions_stmt     // EXTEND WITH HELP: SHOW SESSIONS
| show_tables_stmt       // EXTEND WITH HELP: SHOW TABLES
| show_testing_stmt
| show_trace_stmt        // EXTEND WITH HELP: SHOW TRACE
| show_transaction_stmt  // EXTEND WITH HELP: SHOW TRANSACTION
| show_users_stmt        // EXTEND WITH HELP: SHOW USERS
| show_zone_stmt
| SHOW error             // SHOW HELP: SHOW

// %Help: SHOW SESSION - display session variables
// %Category: Cfg
// %Text: SHOW [SESSION] { <var> | ALL }
// %SeeAlso: WEBDOCS/show-vars.html
show_session_stmt:
  SHOW session_var         { $$.val = &ShowVar{Name: $2} }
| SHOW SESSION session_var { $$.val = &ShowVar{Name: $3} }
| SHOW SESSION error // SHOW HELP: SHOW SESSION

session_var:
  IDENT
// Although ALL, SESSION_USER and DATABASE are identifiers for the
// purpose of SHOW, they lex as separate token types, so they need
// separate rules.
| ALL
| DATABASE
// SET NAMES is standard SQL for SET client_encoding.
// See https://www.postgresql.org/docs/9.6/static/multibyte.html#AEN39236
| NAMES { $$ = "client_encoding" }
| SESSION_USER
// TIME ZONE is special: it is two tokens, but is really the identifier "TIME ZONE".
| TIME ZONE { $$ = "TIME ZONE" }
| TIME error // SHOW HELP: SHOW SESSION

// %Help: SHOW BACKUP - list backup contents
// %Category: CCL
// %Text: SHOW BACKUP <location>
// %SeeAlso: WEBDOCS/show-backup.html
show_backup_stmt:
  SHOW BACKUP string_or_placeholder
  {
    $$.val = &ShowBackup{Path: $3.expr()}
  }
| SHOW BACKUP error // SHOW HELP: SHOW BACKUP

// %Help: SHOW CLUSTER SETTING - display cluster settings
// %Category: Cfg
// %Text:
// SHOW CLUSTER SETTING <var>
// SHOW ALL CLUSTER SETTINGS
// %SeeAlso: WEBDOCS/cluster-settings.html
show_csettings_stmt:
  SHOW CLUSTER SETTING any_name
  {
    $$.val = &ShowClusterSetting{Name: AsStringWithFlags($4.unresolvedName(), FmtBareIdentifiers)}
  }
| SHOW CLUSTER SETTING ALL
  {
    $$.val = &ShowClusterSetting{Name: "all"}
  }
| SHOW CLUSTER error // SHOW HELP: SHOW CLUSTER SETTING
| SHOW ALL CLUSTER SETTINGS
  {
    $$.val = &ShowClusterSetting{Name: "all"}
  }
| SHOW ALL CLUSTER error // SHOW HELP: SHOW CLUSTER SETTING

// %Help: SHOW COLUMNS - list columns in relation
// %Category: DDL
// %Text: SHOW COLUMNS FROM <tablename>
// %SeeAlso: WEBDOCS/show-columns.html
show_columns_stmt:
  SHOW COLUMNS FROM var_name
  {
    $$.val = &ShowColumns{Table: $4.normalizableTableName()}
  }
| SHOW COLUMNS error // SHOW HELP: SHOW COLUMNS

// %Help: SHOW DATABASES - list databases
// %Category: DDL
// %Text: SHOW DATABASES
// %SeeAlso: WEBDOCS/show-databases.html
show_databases_stmt:
  SHOW DATABASES
  {
    $$.val = &ShowDatabases{}
  }
| SHOW DATABASES error // SHOW HELP: SHOW DATABASES

// %Help: SHOW GRANTS - list grants
// %Category: Priv
// %Text: SHOW GRANTS [ON <targets...>] [FOR <users...>]
// %SeeAlso: WEBDOCS/show-grants.html
show_grants_stmt:
  SHOW GRANTS on_privilege_target_clause for_grantee_clause
  {
    $$.val = &ShowGrants{Targets: $3.targetListPtr(), Grantees: $4.nameList()}
  }
| SHOW GRANTS error // SHOW HELP: SHOW GRANTS

// %Help: SHOW INDEXES - list indexes
// %Category: DDL
// %Text: SHOW INDEXES FROM <tablename>
// %SeeAlso: WEBDOCS/show-index.html
show_indexes_stmt:
  SHOW INDEX FROM var_name
  {
    $$.val = &ShowIndex{Table: $4.normalizableTableName()}
  }
| SHOW INDEX error // SHOW HELP: SHOW INDEXES
| SHOW INDEXES FROM var_name
  {
    $$.val = &ShowIndex{Table: $4.normalizableTableName()}
  }
| SHOW INDEXES error // SHOW HELP: SHOW INDEXES
| SHOW KEYS FROM var_name
  {
    $$.val = &ShowIndex{Table: $4.normalizableTableName()}
  }
| SHOW KEYS error // SHOW HELP: SHOW INDEXES

// %Help: SHOW CONSTRAINTS - list constraints
// %Category: DDL
// %Text: SHOW CONSTRAINTS FROM <tablename>
// %SeeAlso: WEBDOCS/show-constraints.html
show_constraints_stmt:
  SHOW CONSTRAINT FROM var_name
  {
    $$.val = &ShowConstraints{Table: $4.normalizableTableName()}
  }
| SHOW CONSTRAINT error // SHOW HELP: SHOW CONSTRAINTS
| SHOW CONSTRAINTS FROM var_name
  {
    $$.val = &ShowConstraints{Table: $4.normalizableTableName()}
  }
| SHOW CONSTRAINTS error // SHOW HELP: SHOW CONSTRAINTS

// %Help: SHOW QUERIES - list running queries
// %Category: Misc
// %Text: SHOW [CLUSTER | LOCAL] QUERIES
// %SeeAlso: CANCEL QUERY
show_queries_stmt:
  SHOW QUERIES
  {
    $$.val = &ShowQueries{Cluster: true}
  }
| SHOW QUERIES error // SHOW HELP: SHOW QUERIES
| SHOW CLUSTER QUERIES
  {
    $$.val = &ShowQueries{Cluster: true}
  }
| SHOW LOCAL QUERIES
  {
    $$.val = &ShowQueries{Cluster: false}
  }

// %Help: SHOW JOBS - list background jobs
// %Category: Misc
// %Text: SHOW JOBS
// %SeeAlso: CANCEL JOB, PAUSE JOB, RESUME JOB
show_jobs_stmt:
  SHOW JOBS
  {
    $$.val = &ShowJobs{}
  }
| SHOW JOBS error // SHOW HELP: SHOW JOBS

// %Help: SHOW TRACE - display an execution trace
// %Category: Misc
// %Text:
// SHOW [KV] TRACE FOR SESSION
// SHOW [KV] TRACE FOR <statement>
// %SeeAlso: EXPLAIN
show_trace_stmt:
  SHOW TRACE FOR SESSION
  {
    $$.val = &ShowTrace{Statement: nil}
  }
| SHOW TRACE error // SHOW HELP: SHOW TRACE
| SHOW KV TRACE FOR SESSION
  {
    $$.val = &ShowTrace{Statement: nil, OnlyKVTrace: true}
  }
| SHOW KV error // SHOW HELP: SHOW TRACE
| SHOW TRACE FOR explainable_stmt
  {
    $$.val = &ShowTrace{Statement: $4.stmt()}
  }
| SHOW KV TRACE FOR explainable_stmt
  {
    $$.val = &ShowTrace{Statement: $5.stmt(), OnlyKVTrace: true }
  }

// %Help: SHOW SESSIONS - list open client sessions
// %Category: Misc
// %Text: SHOW [CLUSTER | LOCAL] SESSIONS
show_sessions_stmt:
  SHOW SESSIONS
  {
    $$.val = &ShowSessions{Cluster: true}
  }
| SHOW SESSIONS error // SHOW HELP: SHOW SESSIONS
| SHOW CLUSTER SESSIONS
  {
    $$.val = &ShowSessions{Cluster: true}
  }
| SHOW LOCAL SESSIONS
  {
    $$.val = &ShowSessions{Cluster: false}
  }

// %Help: SHOW TABLES - list tables
// %Category: DDL
// %Text: SHOW TABLES [FROM <databasename>]
// %SeeAlso: WEBDOCS/show-tables.html
show_tables_stmt:
  SHOW TABLES FROM name
  {
    $$.val = &ShowTables{Database: Name($4)}
  }
| SHOW TABLES
  {
    $$.val = &ShowTables{}
  }
| SHOW TABLES error // SHOW HELP: SHOW TABLES

// %Help: SHOW TRANSACTION - display current transaction properties
// %Category: Cfg
// %Text: SHOW TRANSACTION {ISOLATION LEVEL | PRIORITY | STATUS}
// %SeeAlso: WEBDOCS/show-transaction.html
show_transaction_stmt:
  SHOW TRANSACTION ISOLATION LEVEL
  {
    /* SKIP DOC */
    $$.val = &ShowVar{Name: "TRANSACTION ISOLATION LEVEL"}
  }
| SHOW TRANSACTION PRIORITY
  {
    /* SKIP DOC */
    $$.val = &ShowVar{Name: "TRANSACTION PRIORITY"}
  }
| SHOW TRANSACTION STATUS
  {
    /* SKIP DOC */
    $$.val = &ShowTransactionStatus{}
  }
| SHOW TRANSACTION error // SHOW HELP: SHOW TRANSACTION

// %Help: SHOW CREATE TABLE - display the CREATE TABLE statement for a table
// %Category: DDL
// %Text: SHOW CREATE TABLE <tablename>
// %SeeAlso: WEBDOCS/show-create-table.html
show_create_table_stmt:
  SHOW CREATE TABLE var_name
  {
    $$.val = &ShowCreateTable{Table: $4.normalizableTableName()}
  }
| SHOW CREATE TABLE error // SHOW HELP: SHOW CREATE TABLE

// %Help: SHOW CREATE VIEW - display the CREATE VIEW statement for a view
// %Category: DDL
// %Text: SHOW CREATE VIEW <viewname>
// %SeeAlso: WEBDOCS/show-create-view.html
show_create_view_stmt:
  SHOW CREATE VIEW var_name
  {
    $$.val = &ShowCreateView{View: $4.normalizableTableName()}
  }
| SHOW CREATE VIEW error // SHOW HELP: SHOW CREATE VIEW

// %Help: SHOW USERS - list defined users
// %Category: Priv
// %Text: SHOW USERS
// %SeeAlso: CREATE USER, DROP USER, WEBDOCS/show-users.html
show_users_stmt:
  SHOW USERS
  {
    $$.val = &ShowUsers{}
  }
| SHOW USERS error // SHOW HELP: SHOW USERS

show_zone_stmt:
  EXPERIMENTAL SHOW ZONE CONFIGURATION FOR RANGE unrestricted_name
  {
    /* SKIP DOC */
    $$.val = &ShowZoneConfig{ZoneSpecifier{NamedZone: UnrestrictedName($7)}}
  }
| EXPERIMENTAL SHOW ZONE CONFIGURATION FOR DATABASE name
  {
    /* SKIP DOC */
    $$.val = &ShowZoneConfig{ZoneSpecifier{Database: Name($7)}}
  }
| EXPERIMENTAL SHOW ZONE CONFIGURATION FOR TABLE qualified_name opt_partition
  {
    /* SKIP DOC */
    $$.val = &ShowZoneConfig{ZoneSpecifier{
      TableOrIndex: TableNameWithIndex{Table: $7.normalizableTableName()},
      Partition: Name($8),
    }}
  }
| EXPERIMENTAL SHOW ZONE CONFIGURATION FOR INDEX table_name_with_index opt_partition
  {
    /* SKIP DOC */
    $$.val = &ShowZoneConfig{ZoneSpecifier{
      TableOrIndex: $7.tableWithIdx(),
      Partition: Name($8),
    }}
  }
| EXPERIMENTAL SHOW ZONE CONFIGURATIONS
  {
    /* SKIP DOC */
    $$.val = &ShowZoneConfig{}
  }
| EXPERIMENTAL SHOW ALL ZONE CONFIGURATIONS
  {
    /* SKIP DOC */
    $$.val = &ShowZoneConfig{}
  }

show_testing_stmt:
  SHOW TESTING_RANGES FROM TABLE qualified_name
  {
    /* SKIP DOC */
    $$.val = &ShowRanges{Table: $5.newNormalizableTableName()}
  }
| SHOW TESTING_RANGES FROM INDEX table_name_with_index
  {
    /* SKIP DOC */
    $$.val = &ShowRanges{Index: $5.newTableWithIdx()}
  }
| SHOW EXPERIMENTAL_FINGERPRINTS FROM TABLE qualified_name
  {
    /* SKIP DOC */
    $$.val = &ShowFingerprints{Table: $5.newNormalizableTableName()}
  }

on_privilege_target_clause:
  ON targets
  {
    tmp := $2.targetList()
    $$.val = &tmp
  }
| /* EMPTY */
  {
    $$.val = (*TargetList)(nil)
  }

for_grantee_clause:
  FOR grantee_list
  {
    $$.val = $2.nameList()
  }
| /* EMPTY */
  {
    $$.val = NameList(nil)
  }

// %Help: PAUSE JOB - pause a background job
// %Category: Misc
// %Text: PAUSE JOB <jobid>
// %SeeAlso: SHOW JOBS, CANCEL JOB, RESUME JOB
pause_stmt:
  PAUSE JOB a_expr
  {
    $$.val = &PauseJob{ID: $3.expr()}
  }
| PAUSE error // SHOW HELP: PAUSE JOB

// %Help: CREATE TABLE - create a new table
// %Category: DDL
// %Text:
// CREATE TABLE [IF NOT EXISTS] <tablename> ( <elements...> ) [<interleave>]
// CREATE TABLE [IF NOT EXISTS] <tablename> [( <colnames...> )] AS <source>
//
// Table elements:
//    <name> <type> [<qualifiers...>]
//    [UNIQUE] INDEX [<name>] ( <colname> [ASC | DESC] [, ...] )
//                            [STORING ( <colnames...> )] [<interleave>]
//    FAMILY [<name>] ( <colnames...> )
//    [CONSTRAINT <name>] <constraint>
//
// Table constraints:
//    PRIMARY KEY ( <colnames...> )
//    FOREIGN KEY ( <colnames...> ) REFERENCES <tablename> [( <colnames...> )] [ON DELETE {NO ACTION | RESTRICT}] [ON UPDATE {NO ACTION | RESTRICT}]
//    UNIQUE ( <colnames... ) [STORING ( <colnames...> )] [<interleave>]
//    CHECK ( <expr> )
//
// Column qualifiers:
//   [CONSTRAINT <constraintname>] {NULL | NOT NULL | UNIQUE | PRIMARY KEY | CHECK (<expr>) | DEFAULT <expr>}
//   FAMILY <familyname>, CREATE [IF NOT EXISTS] FAMILY [<familyname>]
//   REFERENCES <tablename> [( <colnames...> )] [ON DELETE {NO ACTION | RESTRICT}] [ON UPDATE {NO ACTION | RESTRICT}]
//   COLLATE <collationname>
//
// Interleave clause:
//    INTERLEAVE IN PARENT <tablename> ( <colnames...> ) [CASCADE | RESTRICT]
//
// %SeeAlso: SHOW TABLES, CREATE VIEW, SHOW CREATE TABLE,
// WEBDOCS/create-table.html
// WEBDOCS/create-table-as.html
create_table_stmt:
  CREATE TABLE any_name '(' opt_table_elem_list ')' opt_interleave opt_partition_by
  {
    $$.val = &CreateTable{
      Table: $3.normalizableTableName(),
      IfNotExists: false,
      Interleave: $7.interleave(),
      Defs: $5.tblDefs(),
      AsSource: nil,
      AsColumnNames: nil,
      PartitionBy: $8.partitionBy(),
    }
  }
| CREATE TABLE IF NOT EXISTS any_name '(' opt_table_elem_list ')' opt_interleave
  {
    $$.val = &CreateTable{Table: $6.normalizableTableName(), IfNotExists: true, Interleave: $10.interleave(), Defs: $8.tblDefs(), AsSource: nil, AsColumnNames: nil}
  }

create_table_as_stmt:
  CREATE TABLE any_name opt_column_list AS select_stmt
  {
    $$.val = &CreateTable{Table: $3.normalizableTableName(), IfNotExists: false, Interleave: nil, Defs: nil, AsSource: $6.slct(), AsColumnNames: $4.nameList()}
  }
| CREATE TABLE IF NOT EXISTS any_name opt_column_list AS select_stmt
  {
    $$.val = &CreateTable{Table: $6.normalizableTableName(), IfNotExists: true, Interleave: nil, Defs: nil, AsSource: $9.slct(), AsColumnNames: $7.nameList()}
  }

opt_table_elem_list:
  table_elem_list
| /* EMPTY */
  {
    $$.val = TableDefs(nil)
  }

table_elem_list:
  table_elem
  {
    $$.val = TableDefs{$1.tblDef()}
  }
| table_elem_list ',' table_elem
  {
    $$.val = append($1.tblDefs(), $3.tblDef())
  }

table_elem:
  column_def
  {
    $$.val = $1.colDef()
  }
| index_def
| family_def
| table_constraint
  {
    $$.val = $1.constraintDef()
  }

opt_interleave:
  INTERLEAVE IN PARENT qualified_name '(' name_list ')' opt_interleave_drop_behavior
  {
    $$.val = &InterleaveDef{
               Parent: $4.newNormalizableTableName(),
               Fields: $6.nameList(),
               DropBehavior: $8.dropBehavior(),
    }
  }
| /* EMPTY */
  {
    $$.val = (*InterleaveDef)(nil)
  }

// TODO(dan): This can be removed in favor of opt_drop_behavior when #7854 is fixed.
opt_interleave_drop_behavior:
  CASCADE
  {
    /* SKIP DOC */
    $$.val = DropCascade
  }
| RESTRICT
  {
    /* SKIP DOC */
    $$.val = DropRestrict
  }
| /* EMPTY */
  {
    $$.val = DropDefault
  }

partition:
  PARTITION unrestricted_name
  {
    $$ = $2
  }

opt_partition:
  partition
| /* EMPTY */
  {
    $$ = ""
  }

opt_partition_by:
  partition_by
| /* EMPTY */
  {
    $$.val = (*PartitionBy)(nil)
  }

partition_by:
  PARTITION BY LIST '(' name_list ')' '(' list_partitions ')'
  {
    $$.val = &PartitionBy{
      Fields: $5.nameList(),
      List: $8.listPartitions(),
    }
  }
| PARTITION BY RANGE '(' name_list ')' '(' range_partitions ')'
  {
    $$.val = &PartitionBy{
      Fields: $5.nameList(),
      Range: $8.rangePartitions(),
    }
  }

list_partitions:
  partition VALUES list_partition_values ',' list_partitions
  {
    $$.val = append([]ListPartition{{
      Name: UnrestrictedName($1),
      Tuples: $3.tuples(),
    }}, $5.listPartitions()...)
  }
| partition VALUES list_partition_values partition_by ',' list_partitions
  {
    $$.val = append([]ListPartition{{
      Name: UnrestrictedName($1),
      Tuples: $3.tuples(),
      Subpartition: $4.partitionBy(),
    }}, $6.listPartitions()...)
  }
| partition VALUES list_partition_values opt_partition_by
  {
    $$.val = []ListPartition{{
      Name: UnrestrictedName($1),
      Tuples: $3.tuples(),
      Subpartition: $4.partitionBy(),
    }}
  }

list_partition_values:
  '(' partition_exprs ')'
  {
    $$.val = []*Tuple{{Exprs: $2.exprs()}}
  }
| list_partition_values ',' '(' partition_exprs ')'
  {
    $$.val = append($1.tuples(), &Tuple{Exprs: $4.exprs()})
  }

partition_exprs:
  partition_expr
  {
    $$.val = Exprs{$1.expr()}
  }
| partition_exprs ',' partition_expr
  {
    $$.val = append($1.exprs(), $3.expr())
  }

partition_expr:
  a_expr
| MAXVALUE
  {
    $$.val = PartitionMaxValue{}
  }

range_partitions:
  partition VALUES LESS THAN '(' partition_exprs ')' ',' range_partitions
  {
    $$.val = append([]RangePartition{{
      Name: UnrestrictedName($1),
      Tuple: &Tuple{Exprs: $6.exprs()},
    }}, $9.rangePartitions()...)
  }
| partition VALUES LESS THAN '(' partition_exprs ')' partition_by ',' range_partitions
  {
    $$.val = append([]RangePartition{{
      Name: UnrestrictedName($1),
      Tuple: &Tuple{Exprs: $6.exprs()},
      Subpartition: $8.partitionBy(),
    }}, $10.rangePartitions()...)
  }
| partition VALUES LESS THAN '(' partition_exprs ')' opt_partition_by
  {
    $$.val = []RangePartition{{
      Name: UnrestrictedName($1),
      Tuple: &Tuple{Exprs: $6.exprs()},
      Subpartition: $8.partitionBy(),
    }}
  }

column_def:
  name typename col_qual_list
  {
    tableDef, err := newColumnTableDef(Name($1), $2.colType(), $3.colQuals())
    if err != nil {
      sqllex.Error(err.Error())
      return 1
    }
    $$.val = tableDef
  }

col_qual_list:
  col_qual_list col_qualification
  {
    $$.val = append($1.colQuals(), $2.colQual())
  }
| /* EMPTY */
  {
    $$.val = []NamedColumnQualification(nil)
  }

col_qualification:
  CONSTRAINT name col_qualification_elem
  {
    $$.val = NamedColumnQualification{Name: Name($2), Qualification: $3.colQualElem()}
  }
| col_qualification_elem
  {
    $$.val = NamedColumnQualification{Qualification: $1.colQualElem()}
  }
| COLLATE unrestricted_name
  {
    $$.val = NamedColumnQualification{Qualification: ColumnCollation($2)}
  }
| FAMILY name
  {
    $$.val = NamedColumnQualification{Qualification: &ColumnFamilyConstraint{Family: Name($2)}}
  }
| CREATE FAMILY opt_name
  {
    $$.val = NamedColumnQualification{Qualification: &ColumnFamilyConstraint{Family: Name($3), Create: true}}
  }
| CREATE IF NOT EXISTS FAMILY name
  {
    $$.val = NamedColumnQualification{Qualification: &ColumnFamilyConstraint{Family: Name($6), Create: true, IfNotExists: true}}
  }

// DEFAULT NULL is already the default for Postgres. But define it here and
// carry it forward into the system to make it explicit.
// - thomas 1998-09-13
//
// WITH NULL and NULL are not SQL-standard syntax elements, so leave them
// out. Use DEFAULT NULL to explicitly indicate that a column may have that
// value. WITH NULL leads to shift/reduce conflicts with WITH TIME ZONE anyway.
// - thomas 1999-01-08
//
// DEFAULT expression must be b_expr not a_expr to prevent shift/reduce
// conflict on NOT (since NOT might start a subsequent NOT NULL constraint, or
// be part of a_expr NOT LIKE or similar constructs).
col_qualification_elem:
  NOT NULL
  {
    $$.val = NotNullConstraint{}
  }
| NULL
  {
    $$.val = NullConstraint{}
  }
| UNIQUE
  {
    $$.val = UniqueConstraint{}
  }
| PRIMARY KEY
  {
    $$.val = PrimaryKeyConstraint{}
  }
| CHECK '(' a_expr ')'
  {
    $$.val = &ColumnCheckConstraint{Expr: $3.expr()}
  }
| DEFAULT b_expr
  {
    $$.val = &ColumnDefault{Expr: $2.expr()}
  }
| REFERENCES qualified_name opt_name_parens key_match reference_actions
 {
    $$.val = &ColumnFKConstraint{
      Table: $2.normalizableTableName(),
      Col: Name($3),
      Actions: $5.referenceActions(),
    }
 }

index_def:
  INDEX opt_name '(' index_params ')' opt_storing opt_interleave
  {
    $$.val = &IndexTableDef{
      Name:    Name($2),
      Columns: $4.idxElems(),
      Storing: $6.nameList(),
      Interleave: $7.interleave(),
    }
  }
| UNIQUE INDEX opt_name '(' index_params ')' opt_storing opt_interleave
  {
    $$.val = &UniqueConstraintTableDef{
      IndexTableDef: IndexTableDef {
        Name:    Name($3),
        Columns: $5.idxElems(),
        Storing: $7.nameList(),
        Interleave: $8.interleave(),
      },
    }
  }

family_def:
  FAMILY opt_name '(' name_list ')'
  {
    $$.val = &FamilyTableDef{
      Name: Name($2),
      Columns: $4.nameList(),
    }
  }

// constraint_elem specifies constraint syntax which is not embedded into a
// column definition. col_qualification_elem specifies the embedded form.
// - thomas 1997-12-03
table_constraint:
  CONSTRAINT name constraint_elem
  {
    $$.val = $3.constraintDef()
    $$.val.(ConstraintTableDef).setName(Name($2))
  }
| constraint_elem
  {
    $$.val = $1.constraintDef()
  }

constraint_elem:
  CHECK '(' a_expr ')'
  {
    $$.val = &CheckConstraintTableDef{
      Expr: $3.expr(),
    }
  }
| UNIQUE '(' index_params ')' opt_storing opt_interleave
  {
    $$.val = &UniqueConstraintTableDef{
      IndexTableDef: IndexTableDef{
        Columns: $3.idxElems(),
        Storing: $5.nameList(),
        Interleave: $6.interleave(),
      },
    }
  }
| PRIMARY KEY '(' index_params ')'
  {
    $$.val = &UniqueConstraintTableDef{
      IndexTableDef: IndexTableDef{
        Columns: $4.idxElems(),
      },
      PrimaryKey:    true,
    }
  }
| FOREIGN KEY '(' name_list ')' REFERENCES qualified_name
    opt_column_list key_match reference_actions
  {
    $$.val = &ForeignKeyConstraintTableDef{
      Table: $7.normalizableTableName(),
      FromCols: $4.nameList(),
      ToCols: $8.nameList(),
      Actions: $10.referenceActions(),
    }
  }

storing:
  COVERING
| STORING

// TODO(pmattis): It would be nice to support a syntax like STORING
// ALL or STORING (*). The syntax addition is straightforward, but we
// need to be careful with the rest of the implementation. In
// particular, columns stored at indexes are currently encoded in such
// a way that adding a new column would require rewriting the existing
// index values. We will need to change the storage format so that it
// is a list of <columnID, value> pairs which will allow both adding
// and dropping columns without rewriting indexes that are storing the
// adjusted column.
opt_storing:
  storing '(' name_list ')'
  {
    $$.val = $3.nameList()
  }
| /* EMPTY */
  {
    $$.val = NameList(nil)
  }

opt_column_list:
  '(' name_list ')'
  {
    $$.val = $2.nameList()
  }
| /* EMPTY */
  {
    $$.val = NameList(nil)
  }

key_match:
  MATCH FULL { return unimplemented(sqllex, "match full") }
| MATCH PARTIAL { return unimplemented(sqllex, "match partial") }
| MATCH SIMPLE { return unimplemented(sqllex, "match simple") }
| /* EMPTY */ {}

// We combine the update and delete actions into one value temporarily for
// simplicity of parsing, and then break them down again in the calling
// production.
reference_actions:
  reference_on_update
  {
     $$.val = ReferenceActions{Update: $1.referenceAction()}
  }
| reference_on_delete
  {
     $$.val = ReferenceActions{Delete: $1.referenceAction()}
  }
| reference_on_update reference_on_delete
  {
    $$.val = ReferenceActions{Update: $1.referenceAction(), Delete: $2.referenceAction()}
  }
| reference_on_delete reference_on_update
  {
    $$.val = ReferenceActions{Delete: $1.referenceAction(), Update: $2.referenceAction()}
  }
| /* EMPTY */
  {
    $$.val = ReferenceActions{}
  }

reference_on_update:
  ON UPDATE reference_action
  {
    $$.val = $3.referenceAction()
  }

reference_on_delete:
  ON DELETE reference_action
  {
    $$.val = $3.referenceAction()
  }

reference_action:
// NO ACTION is currently the default behavior. It is functionally the same as
// RESTRICT.
  NO ACTION
  {
    $$.val = NoAction
  }
| RESTRICT
  {
    $$.val = Restrict
  }
| CASCADE
  {
    $$.val = Cascade
  }
| SET NULL
  {
    $$.val = SetNull
  }
| SET DEFAULT
  {
    $$.val = SetDefault
  }

numeric_only:
  FCONST
  {
    $$.val = $1.numVal()
  }
| '-' FCONST
  {
    $$.val = &NumVal{Value: constant.UnaryOp(token.SUB, $2.numVal().Value, 0)}
  }
| signed_iconst
  {
    $$.val = $1.numVal()
  }

// %Help: TRUNCATE - empty one or more tables
// %Category: DML
// %Text: TRUNCATE [TABLE] <tablename> [, ...] [CASCADE | RESTRICT]
// %SeeAlso: WEBDOCS/truncate.html
truncate_stmt:
  TRUNCATE opt_table relation_expr_list opt_drop_behavior
  {
    $$.val = &Truncate{Tables: $3.tableNameReferences(), DropBehavior: $4.dropBehavior()}
  }
| TRUNCATE error // SHOW HELP: TRUNCATE

// %Help: CREATE USER - define a new user
// %Category: Priv
// %Text: CREATE USER [IF NOT EXISTS] <name> [ [WITH] PASSWORD <passwd> ]
// %SeeAlso: DROP USER, SHOW USERS, WEBDOCS/create-user.html
create_user_stmt:
  CREATE USER string_or_placeholder opt_password
  {
    $$.val = &CreateUser{Name: $3.expr(), Password: $4.expr()}
  }
| CREATE USER IF NOT EXISTS string_or_placeholder opt_password
  {
    $$.val = &CreateUser{Name: $6.expr(), Password: $7.expr(), IfNotExists: true}
  }
| CREATE USER error // SHOW HELP: CREATE USER

opt_password:
  opt_with PASSWORD string_or_placeholder
  {
    $$.val = $3.expr()
  }
| /* EMPTY */
  {
    $$.val = nil
  }

// %Help: CREATE VIEW - create a new view
// %Category: DDL
// %Text: CREATE VIEW <viewname> [( <colnames...> )] AS <source>
// %SeeAlso: CREATE TABLE, SHOW CREATE VIEW, WEBDOCS/create-view.html
create_view_stmt:
  CREATE VIEW any_name opt_column_list AS select_stmt
  {
    $$.val = &CreateView{
      Name: $3.normalizableTableName(),
      ColumnNames: $4.nameList(),
      AsSource: $6.slct(),
    }
  }
| CREATE VIEW error // SHOW HELP: CREATE VIEW

// TODO(a-robinson): CREATE OR REPLACE VIEW support (#2971).

// %Help: CREATE INDEX - create a new index
// %Category: DDL
// %Text:
// CREATE [UNIQUE] INDEX [IF NOT EXISTS] [<idxname>]
//        ON <tablename> ( <colname> [ASC | DESC] [, ...] )
//        [STORING ( <colnames...> )] [<interleave>]
//
// Interleave clause:
//    INTERLEAVE IN PARENT <tablename> ( <colnames...> ) [CASCADE | RESTRICT]
//
// %SeeAlso: CREATE TABLE, SHOW INDEXES, SHOW CREATE INDEX,
// WEBDOCS/create-index.html
create_index_stmt:
  CREATE opt_unique INDEX opt_name ON qualified_name '(' index_params ')' opt_storing opt_interleave
  {
    $$.val = &CreateIndex{
      Name:    Name($4),
      Table:   $6.normalizableTableName(),
      Unique:  $2.bool(),
      Columns: $8.idxElems(),
      Storing: $10.nameList(),
      Interleave: $11.interleave(),
    }
  }
| CREATE opt_unique INDEX IF NOT EXISTS name ON qualified_name '(' index_params ')' opt_storing opt_interleave
  {
    $$.val = &CreateIndex{
      Name:        Name($7),
      Table:       $9.normalizableTableName(),
      Unique:      $2.bool(),
      IfNotExists: true,
      Columns:     $11.idxElems(),
      Storing:     $13.nameList(),
      Interleave: $14.interleave(),
    }
  }
| CREATE opt_unique INDEX error // SHOW HELP: CREATE INDEX

opt_unique:
  UNIQUE
  {
    $$.val = true
  }
| /* EMPTY */
  {
    $$.val = false
  }

index_params:
  index_elem
  {
    $$.val = IndexElemList{$1.idxElem()}
  }
| index_params ',' index_elem
  {
    $$.val = append($1.idxElems(), $3.idxElem())
  }

// Index attributes can be either simple column references, or arbitrary
// expressions in parens. For backwards-compatibility reasons, we allow an
// expression that's just a function call to be written without parens.
index_elem:
  name opt_collate opt_asc_desc
  {
    $$.val = IndexElem{Column: Name($1), Direction: $3.dir()}
  }
| func_expr_windowless opt_collate opt_asc_desc { return unimplemented(sqllex, "index_elem func expr") }
| '(' a_expr ')' opt_collate opt_asc_desc { return unimplemented(sqllex, "index_elem a_expr") }

opt_collate:
  COLLATE unrestricted_name { return unimplementedWithIssue(sqllex, 16619) }
| /* EMPTY */ {}

opt_asc_desc:
  ASC
  {
    $$.val = Ascending
  }
| DESC
  {
    $$.val = Descending
  }
| /* EMPTY */
  {
    $$.val = DefaultDirection
  }

alter_rename_database_stmt:
  ALTER DATABASE name RENAME TO name
  {
    $$.val = &RenameDatabase{Name: Name($3), NewName: Name($6)}
  }

// https://www.postgresql.org/docs/10/static/sql-alteruser.html
alter_user_password_stmt:
  ALTER USER string_or_placeholder WITH PASSWORD string_or_placeholder
  {
    $$.val = &AlterUserSetPassword{Name: $3.expr(), Password: $6.expr()}
  }
| ALTER USER IF EXISTS string_or_placeholder WITH PASSWORD string_or_placeholder
  {
    $$.val = &AlterUserSetPassword{Name: $5.expr(), Password: $8.expr(), IfExists: true}
  }

alter_rename_table_stmt:
  ALTER TABLE relation_expr RENAME TO qualified_name
  {
    $$.val = &RenameTable{Name: $3.normalizableTableName(), NewName: $6.normalizableTableName(), IfExists: false, IsView: false}
  }
| ALTER TABLE IF EXISTS relation_expr RENAME TO qualified_name
  {
    $$.val = &RenameTable{Name: $5.normalizableTableName(), NewName: $8.normalizableTableName(), IfExists: true, IsView: false}
  }
| ALTER TABLE relation_expr RENAME opt_column name TO name
  {
    $$.val = &RenameColumn{Table: $3.normalizableTableName(), Name: Name($6), NewName: Name($8), IfExists: false}
  }
| ALTER TABLE IF EXISTS relation_expr RENAME opt_column name TO name
  {
    $$.val = &RenameColumn{Table: $5.normalizableTableName(), Name: Name($8), NewName: Name($10), IfExists: true}
  }
| ALTER TABLE relation_expr RENAME CONSTRAINT name TO name
  { return unimplemented(sqllex, "alter table rename constraint") }
| ALTER TABLE IF EXISTS relation_expr RENAME CONSTRAINT name TO name
  { return unimplemented(sqllex, "alter table rename constraint") }

alter_rename_view_stmt:
  ALTER VIEW relation_expr RENAME TO qualified_name
  {
    $$.val = &RenameTable{Name: $3.normalizableTableName(), NewName: $6.normalizableTableName(), IfExists: false, IsView: true}
  }
| ALTER VIEW IF EXISTS relation_expr RENAME TO qualified_name
  {
    $$.val = &RenameTable{Name: $5.normalizableTableName(), NewName: $8.normalizableTableName(), IfExists: true, IsView: true}
  }

alter_rename_index_stmt:
  ALTER INDEX table_name_with_index RENAME TO unrestricted_name
  {
    $$.val = &RenameIndex{Index: $3.newTableWithIdx(), NewName: UnrestrictedName($6), IfExists: false}
  }
| ALTER INDEX IF EXISTS table_name_with_index RENAME TO unrestricted_name
  {
    $$.val = &RenameIndex{Index: $5.newTableWithIdx(), NewName: UnrestrictedName($8), IfExists: true}
  }

opt_column:
  COLUMN
  {
    $$.val = true
  }
| /* EMPTY */
  {
    $$.val = false
  }

opt_set_data:
  SET DATA {}
| /* EMPTY */ {}

// %Help: RELEASE - complete a retryable block
// %Category: Txn
// %Text: RELEASE [SAVEPOINT] cockroach_restart
// %SeeAlso: SAVEPOINT, WEBDOCS/savepoint.html
release_stmt:
  RELEASE savepoint_name
  {
    $$.val = &ReleaseSavepoint{Savepoint: $2}
  }
| RELEASE error // SHOW HELP: RELEASE

// %Help: RESUME JOB - resume a background job
// %Category: Misc
// %Text: RESUME JOB <jobid>
// %SeeAlso: SHOW JOBS, CANCEL JOB, PAUSE JOB
resume_stmt:
  RESUME JOB a_expr
  {
    $$.val = &ResumeJob{ID: $3.expr()}
  }
| RESUME error // SHOW HELP: RESUME JOB

// %Help: SAVEPOINT - start a retryable block
// %Category: Txn
// %Text: SAVEPOINT cockroach_restart
// %SeeAlso: RELEASE, WEBDOCS/savepoint.html
savepoint_stmt:
  SAVEPOINT name
  {
    $$.val = &Savepoint{Name: $2}
  }
| SAVEPOINT error // SHOW HELP: SAVEPOINT

// BEGIN / START / COMMIT / END / ROLLBACK / ...
transaction_stmt:
  begin_stmt    // EXTEND WITH HELP: BEGIN
| commit_stmt   // EXTEND WITH HELP: COMMIT
| rollback_stmt // EXTEND WITH HELP: ROLLBACK

// %Help: BEGIN - start a transaction
// %Category: Txn
// %Text:
// BEGIN [TRANSACTION] [ <txnparameter> [[,] ...] ]
// START TRANSACTION [ <txnparameter> [[,] ...] ]
//
// Transaction parameters:
//    ISOLATION LEVEL { SNAPSHOT | SERIALIZABLE }
//    PRIORITY { LOW | NORMAL | HIGH }
//
// %SeeAlso: COMMIT, ROLLBACK, WEBDOCS/begin-transaction.html
begin_stmt:
  BEGIN opt_transaction begin_transaction
  {
    $$.val = $3.stmt()
  }
| BEGIN error // SHOW HELP: BEGIN
| START TRANSACTION begin_transaction
  {
    $$.val = $3.stmt()
  }
| START error // SHOW HELP: BEGIN

// %Help: COMMIT - commit the current transaction
// %Category: Txn
// %Text:
// COMMIT [TRANSACTION]
// END [TRANSACTION]
// %SeeAlso: BEGIN, ROLLBACK, WEBDOCS/commit-transaction.html
commit_stmt:
  COMMIT opt_transaction
  {
    $$.val = &CommitTransaction{}
  }
| COMMIT error // SHOW HELP: COMMIT
| END opt_transaction
  {
    $$.val = &CommitTransaction{}
  }
| END error // SHOW HELP: COMMIT

// %Help: ROLLBACK - abort the current transaction
// %Category: Txn
// %Text: ROLLBACK [TRANSACTION] [TO [SAVEPOINT] cockroach_restart]
// %SeeAlso: BEGIN, COMMIT, SAVEPOINT, WEBDOCS/rollback-transaction.html
rollback_stmt:
  ROLLBACK opt_to_savepoint
  {
    if $2 != "" {
      $$.val = &RollbackToSavepoint{Savepoint: $2}
    } else {
      $$.val = &RollbackTransaction{}
    }
  }
| ROLLBACK error // SHOW HELP: ROLLBACK

opt_transaction:
  TRANSACTION {}
| /* EMPTY */ {}

opt_to_savepoint:
  TRANSACTION
  {
    $$ = ""
  }
| TRANSACTION TO savepoint_name
  {
    $$ = $3
  }
| TO savepoint_name
  {
    $$ = $2
  }
| /* EMPTY */
  {
    $$ = ""
  }

savepoint_name:
  SAVEPOINT name
  {
    $$ = $2
  }
| name
  {
    $$ = $1
  }

begin_transaction:
  transaction_mode_list
  {
    $$.val = &BeginTransaction{Modes: $1.transactionModes()}
  }
| /* EMPTY */
  {
    $$.val = &BeginTransaction{}
  }

transaction_mode_list:
  transaction_mode
  {
    $$.val = $1.transactionModes()
  }
| transaction_mode_list opt_comma transaction_mode
  {
    a := $1.transactionModes()
    b := $3.transactionModes()
    err := a.merge(b)
    if err != nil { sqllex.Error(err.Error()); return 1 }
    $$.val = a
  }

// The transaction mode list after BEGIN should use comma-separated
// modes as per the SQL standard, but PostgreSQL historically allowed
// them to be listed without commas too.
opt_comma:
  ','
  { }
| /* EMPTY */
  { }

transaction_mode:
  transaction_iso_level
  {
    $$.val = TransactionModes{Isolation: $1.isoLevel()}
  }
| transaction_user_priority
  {
    $$.val = TransactionModes{UserPriority: $1.userPriority()}
  }
| transaction_read_mode
  {
    $$.val = TransactionModes{ReadWriteMode: $1.readWriteMode()}
  }

transaction_user_priority:
  PRIORITY user_priority
  {
    $$.val = $2.userPriority()
  }

transaction_iso_level:
  ISOLATION LEVEL iso_level
  {
    $$.val = $3.isoLevel()
  }

transaction_read_mode:
  READ ONLY
  {
    $$.val = ReadOnly
  }
| READ WRITE
  {
    $$.val = ReadWrite
  }

// %Help: CREATE DATABASE - create a new database
// %Category: DDL
// %Text: CREATE DATABASE [IF NOT EXISTS] <name>
// %SeeAlso: WEBDOCS/create-database.html
create_database_stmt:
  CREATE DATABASE name opt_with opt_template_clause opt_encoding_clause opt_lc_collate_clause opt_lc_ctype_clause
  {
    $$.val = &CreateDatabase{
      Name: Name($3),
      Template: $5,
      Encoding: $6,
      Collate: $7,
      CType: $8,
    }
  }
| CREATE DATABASE IF NOT EXISTS name opt_with opt_template_clause opt_encoding_clause opt_lc_collate_clause opt_lc_ctype_clause
  {
    $$.val = &CreateDatabase{
      IfNotExists: true,
      Name: Name($6),
      Template: $8,
      Encoding: $9,
      Collate: $10,
      CType: $11,
    }
   }
| CREATE DATABASE error // SHOW HELP: CREATE DATABASE

opt_template_clause:
  TEMPLATE opt_equal non_reserved_word_or_sconst
  {
    $$ = $3
  }
| /* EMPTY */
  {
    $$ = ""
  }

opt_encoding_clause:
  ENCODING opt_equal non_reserved_word_or_sconst
  {
    $$ = $3
  }
| /* EMPTY */
  {
    $$ = ""
  }

opt_lc_collate_clause:
  LC_COLLATE opt_equal non_reserved_word_or_sconst
  {
    $$ = $3
  }
| /* EMPTY */
  {
    $$ = ""
  }

opt_lc_ctype_clause:
  LC_CTYPE opt_equal non_reserved_word_or_sconst
  {
    $$ = $3
  }
| /* EMPTY */
  {
    $$ = ""
  }

opt_equal:
  '=' {}
| /* EMPTY */ {}

// %Help: INSERT - create new rows in a table
// %Category: DML
// %Text:
// INSERT INTO <tablename> [[AS] <name>] [( <colnames...> )]
//        <selectclause>
//        [ON CONFLICT [( <colnames...> )] {DO UPDATE SET ... [WHERE <expr>] | DO NOTHING}]
//        [RETURNING <exprs...>]
// %SeeAlso: UPSERT, UPDATE, DELETE, WEBDOCS/insert.html
insert_stmt:
  opt_with_clause INSERT INTO insert_target insert_rest returning_clause
  {
    $$.val = $5.stmt()
    $$.val.(*Insert).Table = $4.tblExpr()
    $$.val.(*Insert).Returning = $6.retClause()
  }
| opt_with_clause INSERT INTO insert_target insert_rest on_conflict returning_clause
  {
    $$.val = $5.stmt()
    $$.val.(*Insert).Table = $4.tblExpr()
    $$.val.(*Insert).OnConflict = $6.onConflict()
    $$.val.(*Insert).Returning = $7.retClause()
  }
| opt_with_clause INSERT error // SHOW HELP: INSERT

// %Help: UPSERT - create or replace rows in a table
// %Category: DML
// %Text:
// UPSERT INTO <tablename> [AS <name>] [( <colnames...> )]
//        <selectclause>
//        [RETURNING <exprs...>]
// %SeeAlso: INSERT, UPDATE, DELETE, WEBDOCS/upsert.html
upsert_stmt:
  opt_with_clause UPSERT INTO insert_target insert_rest returning_clause
  {
    $$.val = $5.stmt()
    $$.val.(*Insert).Table = $4.tblExpr()
    $$.val.(*Insert).OnConflict = &OnConflict{}
    $$.val.(*Insert).Returning = $6.retClause()
  }
| opt_with_clause UPSERT error // SHOW HELP: UPSERT

insert_target:
  qualified_name
  {
    $$.val = $1.newNormalizableTableName()
  }
// Can't easily make AS optional here, because VALUES in insert_rest would have
// a shift/reduce conflict with VALUES as an optional alias. We could easily
// allow unreserved_keywords as optional aliases, but that'd be an odd
// divergence from other places. So just require AS for now.
| qualified_name AS name
  {
    $$.val = &AliasedTableExpr{Expr: $1.newNormalizableTableName(), As: AliasClause{Alias: Name($3)}}
  }

insert_rest:
  select_stmt
  {
    $$.val = &Insert{Rows: $1.slct()}
  }
| '(' qualified_name_list ')' select_stmt
  {
    $$.val = &Insert{Columns: $2.unresolvedNames(), Rows: $4.slct()}
  }
| DEFAULT VALUES
  {
    $$.val = &Insert{Rows: &Select{}}
  }

on_conflict:
  ON CONFLICT opt_conf_expr DO UPDATE SET set_clause_list where_clause
  {
    $$.val = &OnConflict{Columns: $3.nameList(), Exprs: $7.updateExprs(), Where: newWhere(astWhere, $8.expr())}
  }
| ON CONFLICT opt_conf_expr DO NOTHING
  {
    $$.val = &OnConflict{Columns: $3.nameList(), DoNothing: true}
  }

opt_conf_expr:
  '(' name_list ')' where_clause
  {
    // TODO(dan): Support the where_clause.
    $$.val = $2.nameList()
  }
| ON CONSTRAINT name { return unimplemented(sqllex, "on conflict on constraint") }
| /* EMPTY */
  {
    $$.val = NameList(nil)
  }

returning_clause:
  RETURNING target_list
  {
    ret := ReturningExprs($2.selExprs())
    $$.val = &ret
  }
| RETURNING NOTHING
  {
    $$.val = returningNothingClause
  }
| /* EMPTY */
  {
    $$.val = AbsentReturningClause
  }

// %Help: UPDATE - update rows of a table
// %Category: DML
// %Text: UPDATE <tablename> [[AS] <name>] SET ... [WHERE <expr>] [RETURNING <exprs...>]
// %SeeAlso: INSERT, UPSERT, DELETE, WEBDOCS/update.html
update_stmt:
  opt_with_clause UPDATE relation_expr_opt_alias
    SET set_clause_list update_from_clause where_clause returning_clause
  {
    $$.val = &Update{Table: $3.tblExpr(), Exprs: $5.updateExprs(), Where: newWhere(astWhere, $7.expr()), Returning: $8.retClause()}
  }
| opt_with_clause UPDATE error // SHOW HELP: UPDATE

// Mark this as unimplemented until the normal from_clause is supported here.
update_from_clause:
  FROM from_list { return unimplementedWithIssue(sqllex, 7841) }
| /* EMPTY */ {}

set_clause_list:
  set_clause
  {
    $$.val = UpdateExprs{$1.updateExpr()}
  }
| set_clause_list ',' set_clause
  {
    $$.val = append($1.updateExprs(), $3.updateExpr())
  }

set_clause:
  single_set_clause
| multiple_set_clause

single_set_clause:
  qualified_name '=' a_expr
  {
    $$.val = &UpdateExpr{Names: UnresolvedNames{$1.unresolvedName()}, Expr: $3.expr()}
  }

multiple_set_clause:
  '(' qualified_name_list ')' '=' in_expr
  {
    $$.val = &UpdateExpr{Tuple: true, Names: $2.unresolvedNames(), Expr: $5.expr()}
  }

// A complete SELECT statement looks like this.
//
// The rule returns either a single select_stmt node or a tree of them,
// representing a set-operation tree.
//
// There is an ambiguity when a sub-SELECT is within an a_expr and there are
// excess parentheses: do the parentheses belong to the sub-SELECT or to the
// surrounding a_expr?  We don't really care, but bison wants to know. To
// resolve the ambiguity, we are careful to define the grammar so that the
// decision is staved off as long as possible: as long as we can keep absorbing
// parentheses into the sub-SELECT, we will do so, and only when it's no longer
// possible to do that will we decide that parens belong to the expression. For
// example, in "SELECT (((SELECT 2)) + 3)" the extra parentheses are treated as
// part of the sub-select. The necessity of doing it that way is shown by
// "SELECT (((SELECT 2)) UNION SELECT 2)". Had we parsed "((SELECT 2))" as an
// a_expr, it'd be too late to go back to the SELECT viewpoint when we see the
// UNION.
//
// This approach is implemented by defining a nonterminal select_with_parens,
// which represents a SELECT with at least one outer layer of parentheses, and
// being careful to use select_with_parens, never '(' select_stmt ')', in the
// expression grammar. We will then have shift-reduce conflicts which we can
// resolve in favor of always treating '(' <select> ')' as a
// select_with_parens. To resolve the conflicts, the productions that conflict
// with the select_with_parens productions are manually given precedences lower
// than the precedence of ')', thereby ensuring that we shift ')' (and then
// reduce to select_with_parens) rather than trying to reduce the inner
// <select> nonterminal to something else. We use UMINUS precedence for this,
// which is a fairly arbitrary choice.
//
// To be able to define select_with_parens itself without ambiguity, we need a
// nonterminal select_no_parens that represents a SELECT structure with no
// outermost parentheses. This is a little bit tedious, but it works.
//
// In non-expression contexts, we use select_stmt which can represent a SELECT
// with or without outer parentheses.
select_stmt:
  select_no_parens %prec UMINUS
| select_with_parens %prec UMINUS
  {
    $$.val = &Select{Select: $1.selectStmt()}
  }

select_with_parens:
  '(' select_no_parens ')'
  {
    $$.val = &ParenSelect{Select: $2.slct()}
  }
| '(' select_with_parens ')'
  {
    $$.val = &ParenSelect{Select: &Select{Select: $2.selectStmt()}}
  }

// This rule parses the equivalent of the standard's <query expression>. The
// duplicative productions are annoying, but hard to get rid of without
// creating shift/reduce conflicts.
//
//      The locking clause (FOR UPDATE etc) may be before or after
//      LIMIT/OFFSET. In <=7.2.X, LIMIT/OFFSET had to be after FOR UPDATE We
//      now support both orderings, but prefer LIMIT/OFFSET before the locking
//      clause.
//      - 2002-08-28 bjm
select_no_parens:
  simple_select
  {
    $$.val = &Select{Select: $1.selectStmt()}
  }
| select_clause sort_clause
  {
    $$.val = &Select{Select: $1.selectStmt(), OrderBy: $2.orderBy()}
  }
| select_clause opt_sort_clause for_locking_clause opt_select_limit
  {
    $$.val = &Select{Select: $1.selectStmt(), OrderBy: $2.orderBy(), LockForUpdate: $3.bool(), Limit: $4.limit()}
  }
| select_clause opt_sort_clause select_limit opt_for_locking_clause
  {
    $$.val = &Select{Select: $1.selectStmt(), OrderBy: $2.orderBy(), Limit: $3.limit(), LockForUpdate: $4.bool()}
  }
| with_clause select_clause
  {
    $$.val = &Select{Select: $2.selectStmt()}
  }
| with_clause select_clause sort_clause
  {
    $$.val = &Select{Select: $2.selectStmt(), OrderBy: $3.orderBy()}
  }
| with_clause select_clause opt_sort_clause for_locking_clause opt_select_limit
  {
    $$.val = &Select{Select: $2.selectStmt(), OrderBy: $3.orderBy(), LockForUpdate: $4.bool(), Limit: $5.limit()}
  }
| with_clause select_clause opt_sort_clause select_limit opt_for_locking_clause
  {
    $$.val = &Select{Select: $2.selectStmt(), OrderBy: $3.orderBy(), Limit: $4.limit(), LockForUpdate: $5.bool()}
  }

select_clause:
// We only provide help if an open parenthesis is provided, because
// otherwise the rule is ambiguous with the top-level statement list.
  '(' error // SHOW HELP: <SELECTCLAUSE>
| simple_select
| select_with_parens

// This rule parses SELECT statements that can appear within set operations,
// including UNION, INTERSECT and EXCEPT. '(' and ')' can be used to specify
// the ordering of the set operations. Without '(' and ')' we want the
// operations to be ordered per the precedence specs at the head of this file.
//
// As with select_no_parens, simple_select cannot have outer parentheses, but
// can have parenthesized subclauses.
//
// Note that sort clauses cannot be included at this level --- SQL requires
//       SELECT foo UNION SELECT bar ORDER BY baz
// to be parsed as
//       (SELECT foo UNION SELECT bar) ORDER BY baz
// not
//       SELECT foo UNION (SELECT bar ORDER BY baz)
//
// Likewise for WITH, FOR UPDATE and LIMIT. Therefore, those clauses are
// described as part of the select_no_parens production, not simple_select.
// This does not limit functionality, because you can reintroduce these clauses
// inside parentheses.
//
// NOTE: only the leftmost component select_stmt should have INTO. However,
// this is not checked by the grammar; parse analysis must check it.
//
// %Help: <SELECTCLAUSE> - access tabular data
// %Category: DML
// %Text:
// Select clause:
//   TABLE <tablename>
//   VALUES ( <exprs...> ) [ , ... ]
//   SELECT ... [ { INTERSECT | UNION | EXCEPT } [ ALL | DISTINCT ] <selectclause> ]
simple_select:
  simple_select_clause // EXTEND WITH HELP: SELECT
| values_clause        // EXTEND WITH HELP: VALUES
| table_clause         // EXTEND WITH HELP: TABLE
| set_operation

// %Help: SELECT - retrieve rows from a data source and compute a result
// %Category: DML
// %Text:
// SELECT [DISTINCT]
//        { <expr> [[AS] <name>] | [ [<dbname>.] <tablename>. ] * } [, ...]
//        [ FROM <source> ]
//        [ WHERE <expr> ]
//        [ GROUP BY <expr> [ , ... ] ]
//        [ HAVING <expr> ]
//        [ WINDOW <name> AS ( <definition> ) ]
//        [ { UNION | INTERSECT | EXCEPT } [ ALL | DISTINCT ] <selectclause> ]
//        [ ORDER BY <expr> [ ASC | DESC ] [, ...] ]
//        [ LIMIT { <expr> | ALL } ]
//        [ OFFSET <expr> [ ROW | ROWS ] ]
//        [ FOR UPDATE ]
// %SeeAlso: WEBDOCS/select.html
simple_select_clause:
  SELECT opt_all_clause target_list
    from_clause where_clause
    group_clause having_clause window_clause
  {
    $$.val = &SelectClause{
      Exprs:   $3.selExprs(),
      From:    $4.from(),
      Where:   newWhere(astWhere, $5.expr()),
      GroupBy: $6.groupBy(),
      Having:  newWhere(astHaving, $7.expr()),
      Window:  $8.window(),
    }
  }
| SELECT distinct_clause target_list
    from_clause where_clause
    group_clause having_clause window_clause
  {
    $$.val = &SelectClause{
      Distinct: $2.bool(),
      Exprs:    $3.selExprs(),
      From:     $4.from(),
      Where:    newWhere(astWhere, $5.expr()),
      GroupBy:  $6.groupBy(),
      Having:   newWhere(astHaving, $7.expr()),
      Window:   $8.window(),
    }
  }
| SELECT error // SHOW HELP: SELECT

set_operation:
  select_clause UNION all_or_distinct select_clause
  {
    $$.val = &UnionClause{
      Type:  UnionOp,
      Left:  &Select{Select: $1.selectStmt()},
      Right: &Select{Select: $4.selectStmt()},
      All:   $3.bool(),
    }
  }
| select_clause INTERSECT all_or_distinct select_clause
  {
    $$.val = &UnionClause{
      Type:  IntersectOp,
      Left:  &Select{Select: $1.selectStmt()},
      Right: &Select{Select: $4.selectStmt()},
      All:   $3.bool(),
    }
  }
| select_clause EXCEPT all_or_distinct select_clause
  {
    $$.val = &UnionClause{
      Type:  ExceptOp,
      Left:  &Select{Select: $1.selectStmt()},
      Right: &Select{Select: $4.selectStmt()},
      All:   $3.bool(),
    }
  }

// %Help: TABLE - select an entire table
// %Category: DML
// %Text: TABLE <tablename>
// %SeeAlso: SELECT, VALUES, WEBDOCS/table-expressions.html
table_clause:
  TABLE table_ref
  {
    $$.val = &SelectClause{
      Exprs:       SelectExprs{starSelectExpr()},
      From:        &From{Tables: TableExprs{$2.tblExpr()}},
      tableSelect: true,
    }
  }
| TABLE error // SHOW HELP: TABLE

// SQL standard WITH clause looks like:
//
// WITH [ RECURSIVE ] <query name> [ (<column> [, ...]) ]
//        AS (query) [ SEARCH or CYCLE clause ]
//
// We don't currently support the SEARCH or CYCLE clause.
//
// Recognizing WITH_LA here allows a CTE to be named TIME or ORDINALITY.
with_clause:
  WITH cte_list { return unimplemented(sqllex, "with cte_list") }
| WITH_LA cte_list { return unimplemented(sqllex, "with cte_list") }
| WITH RECURSIVE cte_list { return unimplemented(sqllex, "with cte_list") }

cte_list:
  common_table_expr { return unimplemented(sqllex, "cte_list") }
| cte_list ',' common_table_expr { return unimplemented(sqllex, "cte_list") }

common_table_expr:
  name opt_name_list AS '(' preparable_stmt ')' { return unimplemented(sqllex, "cte") }

opt_with:
  WITH {}
| /* EMPTY */ {}

opt_with_clause:
  with_clause { return unimplemented(sqllex, "with_clause") }
| /* EMPTY */ {}

opt_table:
  TABLE {}
| /* EMPTY */ {}

all_or_distinct:
  ALL
  {
    $$.val = true
  }
| DISTINCT
  {
    $$.val = false
  }
| /* EMPTY */
  {
    $$.val = false
  }

distinct_clause:
  DISTINCT
  {
    $$.val = true
  }

opt_all_clause:
  ALL {}
| /* EMPTY */ {}

opt_sort_clause:
  sort_clause
  {
    $$.val = $1.orderBy()
  }
| /* EMPTY */
  {
    $$.val = OrderBy(nil)
  }

sort_clause:
  ORDER BY sortby_list
  {
    $$.val = OrderBy($3.orders())
  }

sortby_list:
  sortby
  {
    $$.val = []*Order{$1.order()}
  }
| sortby_list ',' sortby
  {
    $$.val = append($1.orders(), $3.order())
  }

sortby:
  a_expr opt_asc_desc
  {
    $$.val = &Order{OrderType: OrderByColumn, Expr: $1.expr(), Direction: $2.dir()}
  }
| PRIMARY KEY qualified_name opt_asc_desc
  {
    $$.val = &Order{OrderType: OrderByIndex, Direction: $4.dir(), Table: $3.normalizableTableName()}
  }
| INDEX qualified_name '@' unrestricted_name opt_asc_desc
  {
    $$.val = &Order{OrderType: OrderByIndex, Direction: $5.dir(), Table: $2.normalizableTableName(), Index: UnrestrictedName($4) }
  }

// TODO(pmattis): Support ordering using arbitrary math ops?
// | a_expr USING math_op {}

opt_select_limit:
  select_limit
| /* EMPTY */
  {
    $$.val = (*Limit)(nil)
  }

select_limit:
  limit_clause offset_clause
  {
    if $1.limit() == nil {
      $$.val = $2.limit()
    } else {
      $$.val = $1.limit()
      $$.val.(*Limit).Offset = $2.limit().Offset
    }
  }
| offset_clause limit_clause
  {
    $$.val = $1.limit()
    if $2.limit() != nil {
      $$.val.(*Limit).Count = $2.limit().Count
    }
  }
| limit_clause
| offset_clause

opt_limit_clause:
  limit_clause
| /* EMPTY */ { $$.val = (*Limit)(nil) }

limit_clause:
  LIMIT select_limit_value
  {
    if $2.expr() == nil {
      $$.val = (*Limit)(nil)
    } else {
      $$.val = &Limit{Count: $2.expr()}
    }
  }
// SQL:2008 syntax
| FETCH first_or_next opt_select_fetch_first_value row_or_rows ONLY
  {
    $$.val = &Limit{Count: $3.expr()}
  }

offset_clause:
  OFFSET a_expr
  {
    $$.val = &Limit{Offset: $2.expr()}
  }
  // SQL:2008 syntax
  // The trailing ROW/ROWS in this case prevent the full expression
  // syntax. c_expr is the best we can do.
| OFFSET c_expr row_or_rows
  {
    $$.val = &Limit{Offset: $2.expr()}
  }

select_limit_value:
  a_expr
| ALL
  {
    $$.val = Expr(nil)
  }

// Allowing full expressions without parentheses causes various parsing
// problems with the trailing ROW/ROWS key words. SQL only calls for constants,
// so we allow the rest only with parentheses. If omitted, default to 1.
 opt_select_fetch_first_value:
   signed_iconst
   {
     $$.val = $1.expr()
   }
 | '(' a_expr ')'
   {
     $$.val = $2.expr()
   }
 | /* EMPTY */
   {
     $$.val = &NumVal{Value: constant.MakeInt64(1)}
   }

// noise words
row_or_rows:
  ROW {}
| ROWS {}

first_or_next:
  FIRST {}
| NEXT {}

// This syntax for group_clause tries to follow the spec quite closely.
// However, the spec allows only column references, not expressions,
// which introduces an ambiguity between implicit row constructors
// (a,b) and lists of column references.
//
// We handle this by using the a_expr production for what the spec calls
// <ordinary grouping set>, which in the spec represents either one column
// reference or a parenthesized list of column references. Then, we check the
// top node of the a_expr to see if it's an implicit RowExpr, and if so, just
// grab and use the list, discarding the node. (this is done in parse analysis,
// not here)
//
// (we abuse the row_format field of RowExpr to distinguish implicit and
// explicit row constructors; it's debatable if anyone sanely wants to use them
// in a group clause, but if they have a reason to, we make it possible.)
//
// Each item in the group_clause list is either an expression tree or a
// GroupingSet node of some type.
group_clause:
  GROUP BY expr_list
  {
    $$.val = GroupBy($3.exprs())
  }
| /* EMPTY */
  {
    $$.val = GroupBy(nil)
  }

having_clause:
  HAVING a_expr
  {
    $$.val = $2.expr()
  }
| /* EMPTY */
  {
    $$.val = Expr(nil)
  }

opt_for_locking_clause:
  for_locking_clause
| /* EMPTY */
  {
    $$.val = false
  }

for_locking_clause:
  FOR UPDATE
  {
    $$.val = true
  }

// Given "VALUES (a, b)" in a table expression context, we have to
// decide without looking any further ahead whether VALUES is the
// values clause or a set-generating function. Since VALUES is allowed
// as a function name both interpretations are feasible. We resolve
// the shift/reduce conflict by giving the first values_clause
// production a higher precedence than the VALUES token has, causing
// the parser to prefer to reduce, in effect assuming that the VALUES
// is not a function name.
//
// %Help: VALUES - select a given set of values
// %Category: DML
// %Text: VALUES ( <exprs...> ) [, ...]
// %SeeAlso: SELECT, TABLE, WEBDOCS/table-expressions.html
values_clause:
  VALUES '(' expr_list ')' %prec UMINUS
  {
    $$.val = &ValuesClause{[]*Tuple{{Exprs: $3.exprs()}}}
  }
| VALUES error // SHOW HELP: VALUES
| values_clause ',' '(' expr_list ')'
  {
    valNode := $1.selectStmt().(*ValuesClause)
    valNode.Tuples = append(valNode.Tuples, &Tuple{Exprs: $4.exprs()})
    $$.val = valNode
  }

// clauses common to all optimizable statements:
//  from_clause   - allow list of both JOIN expressions and table names
//  where_clause  - qualifications for joins or restrictions

from_clause:
  FROM from_list opt_as_of_clause
  {
    $$.val = &From{Tables: $2.tblExprs(), AsOf: $3.asOfClause()}
  }
| FROM error // SHOW HELP: <SOURCE>
| /* EMPTY */
  {
    $$.val = &From{}
  }

from_list:
  table_ref
  {
    $$.val = TableExprs{$1.tblExpr()}
  }
| from_list ',' table_ref
  {
    $$.val = append($1.tblExprs(), $3.tblExpr())
  }

index_hints_param:
  FORCE_INDEX '=' unrestricted_name
  {
     $$.val = &IndexHints{Index: UnrestrictedName($3)}
  }
| FORCE_INDEX '=' '[' ICONST ']'
  {
    /* SKIP DOC */
    id, err := $4.numVal().AsInt64()
    if err != nil { sqllex.Error(err.Error()); return 1 }
    $$.val = &IndexHints{IndexID: IndexID(id)}
  }
|
  NO_INDEX_JOIN
  {
     $$.val = &IndexHints{NoIndexJoin: true}
  }

index_hints_param_list:
  index_hints_param
  {
    $$.val = $1.indexHints()
  }
|
  index_hints_param_list ',' index_hints_param
  {
    a := $1.indexHints()
    b := $3.indexHints()
    if a.NoIndexJoin && b.NoIndexJoin {
       sqllex.Error("NO_INDEX_JOIN specified multiple times")
       return 1
    }
    if (a.Index != "" || a.IndexID != 0) && (b.Index != "" || b.IndexID != 0) {
       sqllex.Error("FORCE_INDEX specified multiple times")
       return 1
    }
    // At this point either a or b contains "no information"
    // (the empty string for Index and the value 0 for IndexID).
    // Using the addition operator automatically selects the non-zero
    // value, avoiding a conditional branch.
    a.Index = a.Index + b.Index
    a.IndexID = a.IndexID + b.IndexID
    a.NoIndexJoin = a.NoIndexJoin || b.NoIndexJoin
    $$.val = a
  }

opt_index_hints:
  '@' unrestricted_name
  {
    $$.val = &IndexHints{Index: UnrestrictedName($2)}
  }
| '@' '[' ICONST ']'
  {
    id, err := $3.numVal().AsInt64()
    if err != nil { sqllex.Error(err.Error()); return 1 }
    $$.val = &IndexHints{IndexID: IndexID(id)}
  }
| '@' '{' index_hints_param_list '}'
  {
    $$.val = $3.indexHints()
  }
| /* EMPTY */
  {
    $$.val = (*IndexHints)(nil)
  }

// %Help: <SOURCE> - define a data source for SELECT
// %Category: DML
// %Text:
// Data sources:
//   <tablename> [ @ { <idxname> | <indexhint> } ]
//   <tablefunc> ( <exprs...> )
//   ( { <selectclause> | <source> } )
//   <source> [AS] <alias> [( <colnames...> )]
//   <source> { [INNER] | { LEFT | RIGHT | FULL } [OUTER] } JOIN <source> ON <expr>
//   <source> { [INNER] | { LEFT | RIGHT | FULL } [OUTER] } JOIN <source> USING ( <colnames...> )
//   <source> NATURAL { [INNER] | { LEFT | RIGHT | FULL } [OUTER] } JOIN <source>
//   <source> CROSS JOIN <source>
//   <source> WITH ORDINALITY
//   '[' EXPLAIN ... ']'
//   '[' SHOW ... ']'
//
// Index hints:
//   '{' FORCE_INDEX = <idxname> [, ...] '}'
//   '{' NO_INDEX_JOIN [, ...] '}'
//
// %SeeAlso: WEBDOCS/table-expressions.html
table_ref:
  '[' ICONST opt_tableref_col_list alias_clause ']' opt_index_hints opt_ordinality opt_alias_clause
  {
    /* SKIP DOC */
    id, err := $2.numVal().AsInt64()
    if err != nil {
      sqllex.Error(err.Error())
      return 1
    }
    $$.val = &AliasedTableExpr{
                 Expr: &TableRef{
                    TableID: id,
                    Columns: $3.tableRefCols(),
		    As: $4.aliasClause(),
                 },
                 Hints: $6.indexHints(),
                 Ordinality: $7.bool(),
                 As: $8.aliasClause(),
             }
  }
| relation_expr opt_index_hints opt_ordinality opt_alias_clause
  {
    $$.val = &AliasedTableExpr{Expr: $1.newNormalizableTableName(), Hints: $2.indexHints(), Ordinality: $3.bool(), As: $4.aliasClause() }
  }
| qualified_name '(' opt_expr_list ')' opt_ordinality opt_alias_clause
  {
    $$.val = &AliasedTableExpr{Expr: &FuncExpr{Func: $1.resolvableFunctionReference(), Exprs: $3.exprs()}, Ordinality: $5.bool(), As: $6.aliasClause() }
  }
| qualified_name '(' error { return helpWithFunction(sqllex, $1.resolvableFunctionReference()) }
| select_with_parens opt_ordinality opt_alias_clause
  {
    $$.val = &AliasedTableExpr{Expr: &Subquery{Select: $1.selectStmt()}, Ordinality: $2.bool(), As: $3.aliasClause() }
  }
| joined_table
  {
    $$.val = $1.tblExpr()
  }
| '(' joined_table ')' opt_ordinality alias_clause
  {
    $$.val = &AliasedTableExpr{Expr: &ParenTableExpr{$2.tblExpr()}, Ordinality: $4.bool(), As: $5.aliasClause()}
  }

// The following syntax is a CockroachDB extension:
//     SELECT ... FROM [ EXPLAIN .... ] WHERE ...
//     SELECT ... FROM [ SHOW .... ] WHERE ...
//     SELECT ... FROM [ INSERT ... RETURNING ... ] WHERE ...
// A statement within square brackets can be used as a table expression (data source).
// We use square brackets for two reasons:
// - the grammar would be terribly ambiguous if we used simple
//   parentheses or no parentheses at all.
// - it carries visual semantic information, by marking the table
//   expression as radically different from the other things.
//   If a user does not know this and encounters this syntax, they
//   will know from the unusual choice that something rather different
//   is going on and may be pushed by the unusual syntax to
//   investigate further in the docs.

| '[' explainable_stmt ']' opt_ordinality opt_alias_clause
  {
    $$.val = &AliasedTableExpr{Expr: &StatementSource{ Statement: $2.stmt() }, Ordinality: $4.bool(), As: $5.aliasClause() }
  }

opt_tableref_col_list:
  /* EMPTY */               { $$.val = nil }
| '(' ')'                   { $$.val = []ColumnID{} }
| '(' tableref_col_list ')' { $$.val = $2.tableRefCols() }

tableref_col_list:
  ICONST
  {
    id, err := $1.numVal().AsInt64()
    if err != nil { sqllex.Error(err.Error()); return 1 }
    $$.val = []ColumnID{ColumnID(id)}
  }
| tableref_col_list ',' ICONST
  {
    id, err := $3.numVal().AsInt64()
    if err != nil { sqllex.Error(err.Error()); return 1 }
    $$.val = append($1.tableRefCols(), ColumnID(id))
  }

opt_ordinality:
  WITH_LA ORDINALITY
  {
    $$.val = true
  }
| /* EMPTY */
  {
    $$.val = false
  }

// It may seem silly to separate joined_table from table_ref, but there is
// method in SQL's madness: if you don't do it this way you get reduce- reduce
// conflicts, because it's not clear to the parser generator whether to expect
// alias_clause after ')' or not. For the same reason we must treat 'JOIN' and
// 'join_type JOIN' separately, rather than allowing join_type to expand to
// empty; if we try it, the parser generator can't figure out when to reduce an
// empty join_type right after table_ref.
//
// Note that a CROSS JOIN is the same as an unqualified INNER JOIN, and an
// INNER JOIN/ON has the same shape but a qualification expression to limit
// membership. A NATURAL JOIN implicitly matches column names between tables
// and the shape is determined by which columns are in common. We'll collect
// columns during the later transformations.

joined_table:
  '(' joined_table ')'
  {
    $$.val = &ParenTableExpr{Expr: $2.tblExpr()}
  }
| table_ref CROSS JOIN table_ref
  {
    $$.val = &JoinTableExpr{Join: astCrossJoin, Left: $1.tblExpr(), Right: $4.tblExpr()}
  }
| table_ref join_type JOIN table_ref join_qual
  {
    $$.val = &JoinTableExpr{Join: $2, Left: $1.tblExpr(), Right: $4.tblExpr(), Cond: $5.joinCond()}
  }
| table_ref JOIN table_ref join_qual
  {
    $$.val = &JoinTableExpr{Join: astJoin, Left: $1.tblExpr(), Right: $3.tblExpr(), Cond: $4.joinCond()}
  }
| table_ref NATURAL join_type JOIN table_ref
  {
    $$.val = &JoinTableExpr{Join: $3, Left: $1.tblExpr(), Right: $5.tblExpr(), Cond: NaturalJoinCond{}}
  }
| table_ref NATURAL JOIN table_ref
  {
    $$.val = &JoinTableExpr{Join: astJoin, Left: $1.tblExpr(), Right: $4.tblExpr(), Cond: NaturalJoinCond{}}
  }

alias_clause:
  AS name '(' name_list ')'
  {
    $$.val = AliasClause{Alias: Name($2), Cols: $4.nameList()}
  }
| AS name
  {
    $$.val = AliasClause{Alias: Name($2)}
  }
| name '(' name_list ')'
  {
    $$.val = AliasClause{Alias: Name($1), Cols: $3.nameList()}
  }
| name
  {
    $$.val = AliasClause{Alias: Name($1)}
  }

opt_alias_clause:
  alias_clause
| /* EMPTY */
  {
    $$.val = AliasClause{}
  }

opt_as_of_clause:
  AS_LA OF SYSTEM TIME a_expr_const
  {
    $$.val = AsOfClause{Expr: $5.expr()}
  }
| /* EMPTY */
  {
    $$.val = AsOfClause{}
  }

join_type:
  FULL join_outer
  {
    $$ = astFullJoin
  }
| LEFT join_outer
  {
    $$ = astLeftJoin
  }
| RIGHT join_outer
  {
    $$ = astRightJoin
  }
| INNER
  {
    $$ = astInnerJoin
  }

// OUTER is just noise...
join_outer:
  OUTER {}
| /* EMPTY */ {}

// JOIN qualification clauses
// Possibilities are:
//      USING ( column list ) allows only unqualified column names,
//          which must match between tables.
//      ON expr allows more general qualifications.
//
// We return USING as a List node, while an ON-expr will not be a List.
join_qual:
  USING '(' name_list ')'
  {
    $$.val = &UsingJoinCond{Cols: $3.nameList()}
  }
| ON a_expr
  {
    $$.val = &OnJoinCond{Expr: $2.expr()}
  }

relation_expr:
  qualified_name
  {
    $$.val = $1.unresolvedName()
  }
| qualified_name '*'
  {
    $$.val = $1.unresolvedName()
  }
| ONLY qualified_name
  {
    $$.val = $2.unresolvedName()
  }
| ONLY '(' qualified_name ')'
  {
    $$.val = $3.unresolvedName()
  }

relation_expr_list:
  relation_expr
  {
    $$.val = TableNameReferences{$1.unresolvedName()}
  }
| relation_expr_list ',' relation_expr
  {
    $$.val = append($1.tableNameReferences(), $3.unresolvedName())
  }

// Given "UPDATE foo set set ...", we have to decide without looking any
// further ahead whether the first "set" is an alias or the UPDATE's SET
// keyword. Since "set" is allowed as a column name both interpretations are
// feasible. We resolve the shift/reduce conflict by giving the first
// relation_expr_opt_alias production a higher precedence than the SET token
// has, causing the parser to prefer to reduce, in effect assuming that the SET
// is not an alias.
relation_expr_opt_alias:
  relation_expr %prec UMINUS
  {
    $$.val = $1.newNormalizableTableName()
  }
| relation_expr name
  {
    $$.val = &AliasedTableExpr{Expr: $1.newNormalizableTableName(), As: AliasClause{Alias: Name($2)}}
  }
| relation_expr AS name
  {
    $$.val = &AliasedTableExpr{Expr: $1.newNormalizableTableName(), As: AliasClause{Alias: Name($3)}}
  }

where_clause:
  WHERE a_expr
  {
    $$.val = $2.expr()
  }
| /* EMPTY */
  {
    $$.val = Expr(nil)
  }

// Type syntax
//   SQL introduces a large amount of type-specific syntax.
//   Define individual clauses to handle these cases, and use
//   the generic case to handle regular type-extensible Postgres syntax.
//   - thomas 1997-10-10

typename:
  simple_typename opt_array_bounds
  {
    if bounds := $2.int32s(); bounds != nil {
      var err error
      $$.val, err = coltypes.ArrayOf($1.colType(), bounds)
      if err != nil {
        sqllex.Error(err.Error())
        return 1
      }
    } else {
      $$.val = $1.colType()
    }
  }
  // SQL standard syntax, currently only one-dimensional
  // Undocumented but support for potential Postgres compat
| simple_typename ARRAY '[' ICONST ']' {
    /* SKIP DOC */
    var err error
    $$.val, err = coltypes.ArrayOf($1.colType(), []int32{-1})
    if err != nil {
      sqllex.Error(err.Error())
      return 1
    }
  }
| simple_typename ARRAY {
    var err error
    $$.val, err = coltypes.ArrayOf($1.colType(), []int32{-1})
    if err != nil {
      sqllex.Error(err.Error())
      return 1
    }
  }

cast_target:
  typename
  {
    $$.val = $1.colType()
  }
| postgres_oid
  {
    $$.val = $1.castTargetType()
  }

opt_array_bounds:
  // TODO(justin): reintroduce multiple array bounds
  // opt_array_bounds '[' ']' { $$.val = append($1.int32s(), -1) }
  '[' ']' { $$.val = []int32{-1} }
| '[' ICONST ']'
  {
    /* SKIP DOC */
    bound, err := $2.numVal().AsInt32()
    if err != nil {
      sqllex.Error(err.Error())
      return 1
    }
    $$.val = []int32{bound}
  }
| /* EMPTY */ { $$.val = []int32(nil) }

simple_typename:
  numeric
| bit
| character
| const_datetime
| const_interval opt_interval // TODO(pmattis): Support opt_interval?
| const_interval '(' ICONST ')' { return unimplemented(sqllex, "simple_type const_interval") }
| BLOB
  {
    $$.val = coltypes.Blob
  }
| BYTES
  {
    $$.val = coltypes.Bytes
  }
| BYTEA
  {
    $$.val = coltypes.Bytea
  }
| JSONB
  {
    $$.val = coltypes.JSONB
  }
| JSON
  {
    $$.val = coltypes.JSON
  }
| TEXT
  {
    $$.val = coltypes.Text
  }
| NAME
  {
    $$.val = coltypes.Name
  }
| SERIAL
  {
    $$.val = coltypes.Serial
  }
| SMALLSERIAL
  {
    $$.val = coltypes.SmallSerial
  }
| UUID
  {
    $$.val = coltypes.UUID
  }
| INET
  {
    $$.val = coltypes.INet
  }
| BIGSERIAL
  {
    $$.val = coltypes.BigSerial
  }
| OID
  {
    $$.val = coltypes.Oid
  }
| INT2VECTOR
  {
    $$.val = coltypes.Int2vector
  }
| IDENT
  {
    // See https://www.postgresql.org/docs/9.1/static/datatype-character.html
    // Postgres supports a special character type named "char" (with the quotes)
    // that is a single-character column type. It's used by system tables.
    // Eventually this clause will be used to parse user-defined types as well,
    // since their names can be quoted.
    if $1 == "char" {
      $$.val = coltypes.Char
    } else {
      sqllex.Error("syntax error")
      return 1
    }
  }

// We have a separate const_typename to allow defaulting fixed-length types
// such as CHAR() and BIT() to an unspecified length. SQL9x requires that these
// default to a length of one, but this makes no sense for constructs like CHAR
// 'hi' and BIT '0101', where there is an obvious better choice to make. Note
// that const_interval is not included here since it must be pushed up higher
// in the rules to accommodate the postfix options (e.g. INTERVAL '1'
// YEAR). Likewise, we have to handle the generic-type-name case in
// a_expr_const to avoid premature reduce/reduce conflicts against function
// names.
const_typename:
  numeric
| const_bit
| const_character
| const_datetime

opt_numeric_modifiers:
  '(' ICONST ')'
  {
    prec, err := $2.numVal().AsInt64()
    if err != nil {
      sqllex.Error(err.Error())
      return 1
    }
    $$.val = &coltypes.TDecimal{Prec: int(prec)}
  }
| '(' ICONST ',' ICONST ')'
  {
    prec, err := $2.numVal().AsInt64()
    if err != nil {
      sqllex.Error(err.Error())
      return 1
    }
    scale, err := $4.numVal().AsInt64()
    if err != nil {
      sqllex.Error(err.Error())
      return 1
    }
    $$.val = &coltypes.TDecimal{Prec: int(prec), Scale: int(scale)}
  }
| /* EMPTY */
  {
    $$.val = nil
  }

// SQL numeric data types
numeric:
  INT
  {
    $$.val = coltypes.Int
  }
| INT2
    {
      $$.val = coltypes.Int2
    }
| INT4
  {
    $$.val = coltypes.Int4
  }
| INT8
  {
    $$.val = coltypes.Int8
  }
| INT64
  {
    $$.val = coltypes.Int64
  }
| INTEGER
  {
    $$.val = coltypes.Integer
  }
| SMALLINT
  {
    $$.val = coltypes.SmallInt
  }
| BIGINT
  {
    $$.val = coltypes.BigInt
  }
| REAL
  {
    $$.val = coltypes.Real
  }
| FLOAT4
    {
      $$.val = coltypes.Float4
    }
| FLOAT8
    {
      $$.val = coltypes.Float8
    }
| FLOAT opt_float
  {
    nv := $2.numVal()
    prec, err := nv.AsInt64()
    if err != nil {
      sqllex.Error(err.Error())
      return 1
    }
    $$.val = coltypes.NewFloat(int(prec), len(nv.OrigString) > 0)
  }
| DOUBLE PRECISION
  {
    $$.val = coltypes.Double
  }
| DECIMAL opt_numeric_modifiers
  {
    $$.val = $2.colType()
    if $$.val == nil {
      $$.val = coltypes.Decimal
    } else {
      $$.val.(*coltypes.TDecimal).Name = "DECIMAL"
    }
  }
| DEC opt_numeric_modifiers
  {
    $$.val = $2.colType()
    if $$.val == nil {
      $$.val = coltypes.Dec
    } else {
      $$.val.(*coltypes.TDecimal).Name = "DEC"
    }
  }
| NUMERIC opt_numeric_modifiers
  {
    $$.val = $2.colType()
    if $$.val == nil {
      $$.val = coltypes.Numeric
    } else {
      $$.val.(*coltypes.TDecimal).Name = "NUMERIC"
    }
  }
| BOOLEAN
  {
    $$.val = coltypes.Boolean
  }
| BOOL
  {
    $$.val = coltypes.Bool
  }

// Postgres OID pseudo-types. See https://www.postgresql.org/docs/9.4/static/datatype-oid.html.
postgres_oid:
  REGPROC
  {
    $$.val = coltypes.RegProc
  }
| REGPROCEDURE
  {
    $$.val = coltypes.RegProcedure
  }
| REGCLASS
  {
    $$.val = coltypes.RegClass
  }
| REGTYPE
  {
    $$.val = coltypes.RegType
  }
| REGNAMESPACE
  {
    $$.val = coltypes.RegNamespace
  }

opt_float:
  '(' ICONST ')'
  {
    $$.val = $2.numVal()
  }
| /* EMPTY */
  {
    $$.val = &NumVal{Value: constant.MakeInt64(0)}
  }

// SQL bit-field data types
// The following implements BIT() and BIT VARYING().
bit:
  bit_with_length
| bit_without_length

// const_bit is like bit except "BIT" defaults to unspecified length.
// See notes for const_character, which addresses same issue for "CHAR".
const_bit:
  bit_with_length
| bit_without_length

bit_with_length:
  BIT opt_varying '(' ICONST ')'
  {
    n, err := $4.numVal().AsInt64()
    if err != nil {
      sqllex.Error(err.Error())
      return 1
    }
    bit, err := coltypes.NewIntBitType(int(n))
    if err != nil {
      sqllex.Error(err.Error())
      return 1
    }
    $$.val = bit
  }

bit_without_length:
  BIT opt_varying
  {
    $$.val = coltypes.Bit
  }

// SQL character data types
// The following implements CHAR() and VARCHAR().
character:
  character_with_length
| character_without_length

const_character:
  character_with_length
| character_without_length

character_with_length:
  character_base '(' ICONST ')'
  {
    n, err := $3.numVal().AsInt64()
    if err != nil {
      sqllex.Error(err.Error())
      return 1
    }
    $$.val = $1.colType()
    if n != 0 {
      strType := &coltypes.TString{N: int(n)}
      strType.Name = $$.val.(*coltypes.TString).Name
      $$.val = strType
    }
  }

character_without_length:
  character_base
  {
    $$.val = $1.colType()
  }

character_base:
  CHARACTER opt_varying
  {
    $$.val = coltypes.Char
  }
| CHAR opt_varying
  {
    $$.val = coltypes.Char
  }
| VARCHAR
  {
    $$.val = coltypes.VarChar
  }
| STRING
  {
    $$.val = coltypes.String
  }

opt_varying:
  VARYING {}
| /* EMPTY */ {}

// SQL date/time types
const_datetime:
  DATE
  {
    $$.val = coltypes.Date
  }
| TIMESTAMP
  {
    $$.val = coltypes.Timestamp
  }
| TIMESTAMP WITHOUT TIME ZONE
  {
    $$.val = coltypes.Timestamp
  }
| TIMESTAMPTZ
  {
    $$.val = coltypes.TimestampWithTZ
  }
| TIMESTAMP WITH_LA TIME ZONE
  {
    $$.val = coltypes.TimestampWithTZ
  }

const_interval:
  INTERVAL {
    $$.val = coltypes.Interval
  }

opt_interval:
  YEAR
  {
    $$.val = year
  }
| MONTH
  {
    $$.val = month
  }
| DAY
  {
    $$.val = day
  }
| HOUR
  {
    $$.val = hour
  }
| MINUTE
  {
    $$.val = minute
  }
| interval_second
  {
    $$.val = $1.durationField()
  }
// Like Postgres, we ignore the left duration field. See explanation:
// https://www.postgresql.org/message-id/20110510040219.GD5617%40tornado.gateway.2wire.net
| YEAR TO MONTH
  {
    $$.val = month
  }
| DAY TO HOUR
  {
    $$.val = hour
  }
| DAY TO MINUTE
  {
    $$.val = minute
  }
| DAY TO interval_second
  {
    $$.val = $3.durationField()
  }
| HOUR TO MINUTE
  {
    $$.val = minute
  }
| HOUR TO interval_second
  {
    $$.val = $3.durationField()
  }
| MINUTE TO interval_second
  {
    $$.val = $3.durationField()
  }
| /* EMPTY */
  {
    $$.val = nil
  }

interval_second:
  SECOND
  {
    $$.val = second
  }
| SECOND '(' ICONST ')' { return unimplemented(sqllex, "interval_second") }

// General expressions. This is the heart of the expression syntax.
//
// We have two expression types: a_expr is the unrestricted kind, and b_expr is
// a subset that must be used in some places to avoid shift/reduce conflicts.
// For example, we can't do BETWEEN as "BETWEEN a_expr AND a_expr" because that
// use of AND conflicts with AND as a boolean operator. So, b_expr is used in
// BETWEEN and we remove boolean keywords from b_expr.
//
// Note that '(' a_expr ')' is a b_expr, so an unrestricted expression can
// always be used by surrounding it with parens.
//
// c_expr is all the productions that are common to a_expr and b_expr; it's
// factored out just to eliminate redundant coding.
//
// Be careful of productions involving more than one terminal token. By
// default, bison will assign such productions the precedence of their last
// terminal, but in nearly all cases you want it to be the precedence of the
// first terminal instead; otherwise you will not get the behavior you expect!
// So we use %prec annotations freely to set precedences.
a_expr:
  c_expr
| a_expr TYPECAST cast_target
  {
    $$.val = &CastExpr{Expr: $1.expr(), Type: $3.castTargetType(), syntaxMode: castShort}
  }
| a_expr TYPEANNOTATE typename
  {
    $$.val = &AnnotateTypeExpr{Expr: $1.expr(), Type: $3.colType(), syntaxMode: annotateShort}
  }
| a_expr COLLATE unrestricted_name
  {
    $$.val = &CollateExpr{Expr: $1.expr(), Locale: $3}
  }
| a_expr AT TIME ZONE a_expr %prec AT { return unimplemented(sqllex, "at tz") }
  // These operators must be called out explicitly in order to make use of
  // bison's automatic operator-precedence handling. All other operator names
  // are handled by the generic productions using "OP", below; and all those
  // operators will have the same precedence.
  //
  // If you add more explicitly-known operators, be sure to add them also to
  // b_expr and to the math_op list below.
| '+' a_expr %prec UMINUS
  {
    $$.val = &UnaryExpr{Operator: UnaryPlus, Expr: $2.expr()}
  }
| '-' a_expr %prec UMINUS
  {
    $$.val = &UnaryExpr{Operator: UnaryMinus, Expr: $2.expr()}
  }
| '~' a_expr %prec UMINUS
  {
    $$.val = &UnaryExpr{Operator: UnaryComplement, Expr: $2.expr()}
  }
| a_expr '+' a_expr
  {
    $$.val = &BinaryExpr{Operator: Plus, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '-' a_expr
  {
    $$.val = &BinaryExpr{Operator: Minus, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '*' a_expr
  {
    $$.val = &BinaryExpr{Operator: Mult, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '/' a_expr
  {
    $$.val = &BinaryExpr{Operator: Div, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr FLOORDIV a_expr
  {
    $$.val = &BinaryExpr{Operator: FloorDiv, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '%' a_expr
  {
    $$.val = &BinaryExpr{Operator: Mod, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '^' a_expr
  {
    $$.val = &BinaryExpr{Operator: Pow, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '#' a_expr
  {
    $$.val = &BinaryExpr{Operator: Bitxor, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '&' a_expr
  {
    $$.val = &BinaryExpr{Operator: Bitand, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '|' a_expr
  {
    $$.val = &BinaryExpr{Operator: Bitor, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '<' a_expr
  {
    $$.val = &ComparisonExpr{Operator: LT, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '>' a_expr
  {
    $$.val = &ComparisonExpr{Operator: GT, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '?' a_expr
  {
    $$.val = &ComparisonExpr{Operator: Existence, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr SOME_EXISTENCE a_expr
  {
    $$.val = &ComparisonExpr{Operator: SomeExistence, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr ALL_EXISTENCE a_expr
  {
    $$.val = &ComparisonExpr{Operator: AllExistence, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr CONTAINS a_expr
  {
    $$.val = &ComparisonExpr{Operator: Contains, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr CONTAINED_BY a_expr
  {
    $$.val = &ComparisonExpr{Operator: ContainedBy, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr '=' a_expr
  {
    $$.val = &ComparisonExpr{Operator: EQ, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr CONCAT a_expr
  {
    $$.val = &BinaryExpr{Operator: Concat, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr LSHIFT a_expr
  {
    $$.val = &BinaryExpr{Operator: LShift, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr RSHIFT a_expr
  {
    $$.val = &BinaryExpr{Operator: RShift, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr FETCHVAL a_expr
  {
    $$.val = &BinaryExpr{Operator: FetchVal, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr FETCHTEXT a_expr
  {
    $$.val = &BinaryExpr{Operator: FetchText, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr FETCHVAL_PATH a_expr
  {
    $$.val = &BinaryExpr{Operator: FetchValPath, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr FETCHTEXT_PATH a_expr
  {
    $$.val = &BinaryExpr{Operator: FetchTextPath, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr REMOVE_PATH a_expr
  {
    $$.val = &FuncExpr{Func: wrapFunction("JSON_REMOVE_PATH"), Exprs: Exprs{$1.expr(), $3.expr()}}
  }
| a_expr LESS_EQUALS a_expr
  {
    $$.val = &ComparisonExpr{Operator: LE, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr GREATER_EQUALS a_expr
  {
    $$.val = &ComparisonExpr{Operator: GE, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr NOT_EQUALS a_expr
  {
    $$.val = &ComparisonExpr{Operator: NE, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr AND a_expr
  {
    $$.val = &AndExpr{Left: $1.expr(), Right: $3.expr()}
  }
| a_expr OR a_expr
  {
    $$.val = &OrExpr{Left: $1.expr(), Right: $3.expr()}
  }
| NOT a_expr
  {
    $$.val = &NotExpr{Expr: $2.expr()}
  }
| NOT_LA a_expr %prec NOT
  {
    $$.val = &NotExpr{Expr: $2.expr()}
  }
| a_expr LIKE a_expr
  {
    $$.val = &ComparisonExpr{Operator: Like, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr NOT_LA LIKE a_expr %prec NOT_LA
  {
    $$.val = &ComparisonExpr{Operator: NotLike, Left: $1.expr(), Right: $4.expr()}
  }
| a_expr ILIKE a_expr
  {
    $$.val = &ComparisonExpr{Operator: ILike, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr NOT_LA ILIKE a_expr %prec NOT_LA
  {
    $$.val = &ComparisonExpr{Operator: NotILike, Left: $1.expr(), Right: $4.expr()}
  }
| a_expr SIMILAR TO a_expr %prec SIMILAR
  {
    $$.val = &ComparisonExpr{Operator: SimilarTo, Left: $1.expr(), Right: $4.expr()}
  }
| a_expr NOT_LA SIMILAR TO a_expr %prec NOT_LA
  {
    $$.val = &ComparisonExpr{Operator: NotSimilarTo, Left: $1.expr(), Right: $5.expr()}
  }
| a_expr '~' a_expr
  {
    $$.val = &ComparisonExpr{Operator: RegMatch, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr NOT_REGMATCH a_expr
  {
    $$.val = &ComparisonExpr{Operator: NotRegMatch, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr REGIMATCH a_expr
  {
    $$.val = &ComparisonExpr{Operator: RegIMatch, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr NOT_REGIMATCH a_expr
  {
    $$.val = &ComparisonExpr{Operator: NotRegIMatch, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr IS NAN %prec IS
  {
    $$.val = &ComparisonExpr{Operator: EQ, Left: $1.expr(), Right: NewStrVal("NaN")}
  }
| a_expr IS NOT NAN %prec IS
  {
    $$.val = &ComparisonExpr{Operator: NE, Left: $1.expr(), Right: NewStrVal("NaN")}
  }
| a_expr IS NULL %prec IS
  {
    $$.val = &ComparisonExpr{Operator: Is, Left: $1.expr(), Right: DNull}
  }
| a_expr IS NOT NULL %prec IS
  {
    $$.val = &ComparisonExpr{Operator: IsNot, Left: $1.expr(), Right: DNull}
  }
| row OVERLAPS row { return unimplemented(sqllex, "overlaps") }
| a_expr IS TRUE %prec IS
  {
    $$.val = &ComparisonExpr{Operator: Is, Left: $1.expr(), Right: MakeDBool(true)}
  }
| a_expr IS NOT TRUE %prec IS
  {
    $$.val = &ComparisonExpr{Operator: IsNot, Left: $1.expr(), Right: MakeDBool(true)}
  }
| a_expr IS FALSE %prec IS
  {
    $$.val = &ComparisonExpr{Operator: Is, Left: $1.expr(), Right: MakeDBool(false)}
  }
| a_expr IS NOT FALSE %prec IS
  {
    $$.val = &ComparisonExpr{Operator: IsNot, Left: $1.expr(), Right: MakeDBool(false)}
  }
| a_expr IS UNKNOWN %prec IS
  {
    $$.val = &ComparisonExpr{Operator: Is, Left: $1.expr(), Right: DNull}
  }
| a_expr IS NOT UNKNOWN %prec IS
  {
    $$.val = &ComparisonExpr{Operator: IsNot, Left: $1.expr(), Right: DNull}
  }
| a_expr IS DISTINCT FROM a_expr %prec IS
  {
    $$.val = &ComparisonExpr{Operator: IsDistinctFrom, Left: $1.expr(), Right: $5.expr()}
  }
| a_expr IS NOT DISTINCT FROM a_expr %prec IS
  {
    $$.val = &ComparisonExpr{Operator: IsNotDistinctFrom, Left: $1.expr(), Right: $6.expr()}
  }
| a_expr IS OF '(' type_list ')' %prec IS
  {
    $$.val = &IsOfTypeExpr{Expr: $1.expr(), Types: $5.colTypes()}
  }
| a_expr IS NOT OF '(' type_list ')' %prec IS
  {
    $$.val = &IsOfTypeExpr{Not: true, Expr: $1.expr(), Types: $6.colTypes()}
  }
| a_expr BETWEEN opt_asymmetric b_expr AND a_expr %prec BETWEEN
  {
    $$.val = &RangeCond{Left: $1.expr(), From: $4.expr(), To: $6.expr()}
  }
| a_expr NOT_LA BETWEEN opt_asymmetric b_expr AND a_expr %prec NOT_LA
  {
    $$.val = &RangeCond{Not: true, Left: $1.expr(), From: $5.expr(), To: $7.expr()}
  }
| a_expr BETWEEN SYMMETRIC b_expr AND a_expr %prec BETWEEN
  {
    $$.val = &RangeCond{Left: $1.expr(), From: $4.expr(), To: $6.expr()}
  }
| a_expr NOT_LA BETWEEN SYMMETRIC b_expr AND a_expr %prec NOT_LA
  {
    $$.val = &RangeCond{Not: true, Left: $1.expr(), From: $5.expr(), To: $7.expr()}
  }
| a_expr IN in_expr
  {
    $$.val = &ComparisonExpr{Operator: In, Left: $1.expr(), Right: $3.expr()}
  }
| a_expr NOT_LA IN in_expr %prec NOT_LA
  {
    $$.val = &ComparisonExpr{Operator: NotIn, Left: $1.expr(), Right: $4.expr()}
  }
| a_expr subquery_op sub_type a_expr %prec CONCAT
  {
    op := $3.cmpOp()
    subOp := $2.op()
    subOpCmp, ok := subOp.(ComparisonOperator)
    if !ok {
      sqllex.Error(fmt.Sprintf("%s %s <array> is invalid because %q is not a boolean operator",
        subOp, op, subOp))
      return 1
    }
    $$.val = &ComparisonExpr{
      Operator: op,
      SubOperator: subOpCmp,
      Left: $1.expr(),
      Right: $4.expr(),
    }
  }
| DEFAULT
  {
    $$.val = DefaultVal{}
  }
// | UNIQUE select_with_parens { return unimplemented(sqllex) }

// Restricted expressions
//
// b_expr is a subset of the complete expression syntax defined by a_expr.
//
// Presently, AND, NOT, IS, and IN are the a_expr keywords that would cause
// trouble in the places where b_expr is used. For simplicity, we just
// eliminate all the boolean-keyword-operator productions from b_expr.
b_expr:
  c_expr
| b_expr TYPECAST cast_target
  {
    $$.val = &CastExpr{Expr: $1.expr(), Type: $3.castTargetType(), syntaxMode: castShort}
  }
| b_expr TYPEANNOTATE typename
  {
    $$.val = &AnnotateTypeExpr{Expr: $1.expr(), Type: $3.colType(), syntaxMode: annotateShort}
  }
| '+' b_expr %prec UMINUS
  {
    $$.val = &UnaryExpr{Operator: UnaryPlus, Expr: $2.expr()}
  }
| '-' b_expr %prec UMINUS
  {
    $$.val = &UnaryExpr{Operator: UnaryMinus, Expr: $2.expr()}
  }
| '~' b_expr %prec UMINUS
  {
    $$.val = &UnaryExpr{Operator: UnaryComplement, Expr: $2.expr()}
  }
| b_expr '+' b_expr
  {
    $$.val = &BinaryExpr{Operator: Plus, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr '-' b_expr
  {
    $$.val = &BinaryExpr{Operator: Minus, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr '*' b_expr
  {
    $$.val = &BinaryExpr{Operator: Mult, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr '/' b_expr
  {
    $$.val = &BinaryExpr{Operator: Div, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr FLOORDIV b_expr
  {
    $$.val = &BinaryExpr{Operator: FloorDiv, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr '%' b_expr
  {
    $$.val = &BinaryExpr{Operator: Mod, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr '^' b_expr
  {
    $$.val = &BinaryExpr{Operator: Pow, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr '#' b_expr
  {
    $$.val = &BinaryExpr{Operator: Bitxor, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr '&' b_expr
  {
    $$.val = &BinaryExpr{Operator: Bitand, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr '|' b_expr
  {
    $$.val = &BinaryExpr{Operator: Bitor, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr '<' b_expr
  {
    $$.val = &ComparisonExpr{Operator: LT, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr '>' b_expr
  {
    $$.val = &ComparisonExpr{Operator: GT, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr '=' b_expr
  {
    $$.val = &ComparisonExpr{Operator: EQ, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr CONCAT b_expr
  {
    $$.val = &BinaryExpr{Operator: Concat, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr LSHIFT b_expr
  {
    $$.val = &BinaryExpr{Operator: LShift, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr RSHIFT b_expr
  {
    $$.val = &BinaryExpr{Operator: RShift, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr LESS_EQUALS b_expr
  {
    $$.val = &ComparisonExpr{Operator: LE, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr GREATER_EQUALS b_expr
  {
    $$.val = &ComparisonExpr{Operator: GE, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr NOT_EQUALS b_expr
  {
    $$.val = &ComparisonExpr{Operator: NE, Left: $1.expr(), Right: $3.expr()}
  }
| b_expr IS DISTINCT FROM b_expr %prec IS
  {
    $$.val = &ComparisonExpr{Operator: IsDistinctFrom, Left: $1.expr(), Right: $5.expr()}
  }
| b_expr IS NOT DISTINCT FROM b_expr %prec IS
  {
    $$.val = &ComparisonExpr{Operator: IsNotDistinctFrom, Left: $1.expr(), Right: $6.expr()}
  }
| b_expr IS OF '(' type_list ')' %prec IS
  {
    $$.val = &IsOfTypeExpr{Expr: $1.expr(), Types: $5.colTypes()}
  }
| b_expr IS NOT OF '(' type_list ')' %prec IS
  {
    $$.val = &IsOfTypeExpr{Not: true, Expr: $1.expr(), Types: $6.colTypes()}
  }

// Productions that can be used in both a_expr and b_expr.
//
// Note: productions that refer recursively to a_expr or b_expr mostly cannot
// appear here. However, it's OK to refer to a_exprs that occur inside
// parentheses, such as function arguments; that cannot introduce ambiguity to
// the b_expr syntax.
c_expr:
  d_expr
| d_expr array_subscripts
  {
    $$.val = &IndirectionExpr{
      Expr: $1.expr(),
      Indirection: $2.arraySubscripts(),
    }
  }
| case_expr
| EXISTS select_with_parens
  {
    $$.val = &ExistsExpr{Subquery: &Subquery{Select: $2.selectStmt()}}
  }

// Productions that can be followed by a postfix operator.
//
// Currently we support array indexing (see c_expr above), but these
// are also the expressions which later can be followed with `.xxx` when
// we support field subscripting syntax.
d_expr:
  qualified_name
  {
    $$.val = $1.unresolvedName()
  }
| a_expr_const
| '@' ICONST
  {
    colNum, err := $2.numVal().AsInt64()
    if err != nil {
      sqllex.Error(err.Error())
      return 1
    }
    if colNum < 1 || colNum > int64(MaxInt) {
      sqllex.Error(fmt.Sprintf("invalid column ordinal: @%d", colNum))
      return 1
    }
    $$.val = NewOrdinalReference(int(colNum-1))
  }
| PLACEHOLDER
  {
    $$.val = NewPlaceholder($1)
  }
| '(' a_expr ')'
  {
    $$.val = &ParenExpr{Expr: $2.expr()}
  }
| func_expr
| select_with_parens %prec UMINUS
  {
    $$.val = &Subquery{Select: $1.selectStmt()}
  }
| ARRAY select_with_parens
  {
    $$.val = &ArrayFlatten{Subquery: &Subquery{Select: $2.selectStmt()}}
  }
| ARRAY array_expr
  {
    $$.val = $2.expr()
  }
| explicit_row
  {
    $$.val = $1.expr()
  }
| implicit_row
  {
    $$.val = $1.expr()
  }
// TODO(pmattis): Support this notation?
// | GROUPING '(' expr_list ')' { return unimplemented(sqllex) }

func_application:
  func_name '(' ')'
  {
    $$.val = &FuncExpr{Func: $1.resolvableFunctionReference()}
  }
| func_name '(' expr_list opt_sort_clause ')'
  {
    $$.val = &FuncExpr{Func: $1.resolvableFunctionReference(), Exprs: $3.exprs()}
  }
| func_name '(' VARIADIC a_expr opt_sort_clause ')' { return unimplemented(sqllex, "variadic") }
| func_name '(' expr_list ',' VARIADIC a_expr opt_sort_clause ')' { return unimplemented(sqllex, "variadic") }
| func_name '(' ALL expr_list opt_sort_clause ')'
  {
    $$.val = &FuncExpr{Func: $1.resolvableFunctionReference(), Type: AllFuncType, Exprs: $4.exprs()}
  }
| func_name '(' DISTINCT expr_list opt_sort_clause ')'
  {
    $$.val = &FuncExpr{Func: $1.resolvableFunctionReference(), Type: DistinctFuncType, Exprs: $4.exprs()}
  }
| func_name '(' '*' ')'
  {
    $$.val = &FuncExpr{Func: $1.resolvableFunctionReference(), Exprs: Exprs{StarExpr()}}
  }
| func_name '(' error { return helpWithFunction(sqllex, $1.resolvableFunctionReference()) }

// func_expr and its cousin func_expr_windowless are split out from c_expr just
// so that we have classifications for "everything that is a function call or
// looks like one". This isn't very important, but it saves us having to
// document which variants are legal in places like "FROM function()" or the
// backwards-compatible functional-index syntax for CREATE INDEX. (Note that
// many of the special SQL functions wouldn't actually make any sense as
// functional index entries, but we ignore that consideration here.)
func_expr:
  func_application within_group_clause filter_clause over_clause
  {
    f := $1.expr().(*FuncExpr)
    f.Filter = $3.expr()
    f.WindowDef = $4.windowDef()
    $$.val = f
  }
| func_expr_common_subexpr
  {
    $$.val = $1.expr()
  }

// As func_expr but does not accept WINDOW functions directly (but they can
// still be contained in arguments for functions etc). Use this when window
// expressions are not allowed, where needed to disambiguate the grammar
// (e.g. in CREATE INDEX).
func_expr_windowless:
  func_application { return unimplemented(sqllex, "func_application") }
| func_expr_common_subexpr { return unimplemented(sqllex, "func_expr_common_subexpr") }

// Special expressions that are considered to be functions.
func_expr_common_subexpr:
  COLLATION FOR '(' a_expr ')' { return unimplemented(sqllex, "func_expr_common_subexpr collation") }
| CURRENT_DATE
  {
    $$.val = &FuncExpr{Func: wrapFunction($1)}
  }
| CURRENT_DATE '(' ')'
  {
    $$.val = &FuncExpr{Func: wrapFunction($1)}
  }
| CURRENT_DATE '(' error { return helpWithFunction(sqllex, ResolvableFunctionReference{UnresolvedName{Name($1)}}) }
| CURRENT_SCHEMA
  {
    $$.val = &FuncExpr{Func: wrapFunction($1)}
  }
| CURRENT_SCHEMA '(' ')'
  {
    $$.val = &FuncExpr{Func: wrapFunction($1)}
  }
| CURRENT_SCHEMA '(' error { return helpWithFunction(sqllex, ResolvableFunctionReference{UnresolvedName{Name($1)}}) }
| CURRENT_TIMESTAMP
  {
    $$.val = &FuncExpr{Func: wrapFunction($1)}
  }
| CURRENT_TIMESTAMP '(' ')'
  {
    $$.val = &FuncExpr{Func: wrapFunction($1)}
  }
| CURRENT_TIMESTAMP '(' error { return helpWithFunction(sqllex, ResolvableFunctionReference{UnresolvedName{Name($1)}}) }
| CURRENT_ROLE { return unimplemented(sqllex, "current role") }
| CURRENT_USER
  {
    $$.val = &FuncExpr{Func: wrapFunction($1)}
  }
| CURRENT_USER '(' ')'
  {
    $$.val = &FuncExpr{Func: wrapFunction($1)}
  }
| CURRENT_USER '(' error { return helpWithFunction(sqllex, ResolvableFunctionReference{UnresolvedName{Name($1)}}) }
| SESSION_USER
  {
    $$.val = &FuncExpr{Func: wrapFunction("current_user")}
  }
| USER
  {
    $$.val = &FuncExpr{Func: wrapFunction("current_user")}
  }
| CAST '(' a_expr AS cast_target ')'
  {
    $$.val = &CastExpr{Expr: $3.expr(), Type: $5.castTargetType(), syntaxMode: castExplicit}
  }
| ANNOTATE_TYPE '(' a_expr ',' typename ')'
  {
    $$.val = &AnnotateTypeExpr{Expr: $3.expr(), Type: $5.colType(), syntaxMode: annotateExplicit}
  }
| EXTRACT '(' extract_list ')'
  {
    $$.val = &FuncExpr{Func: wrapFunction($1), Exprs: $3.exprs()}
  }
| EXTRACT '(' error { return helpWithFunction(sqllex, ResolvableFunctionReference{UnresolvedName{Name($1)}}) }
| EXTRACT_DURATION '(' extract_list ')'
  {
    $$.val = &FuncExpr{Func: wrapFunction($1), Exprs: $3.exprs()}
  }
| EXTRACT_DURATION '(' error { return helpWithFunction(sqllex, ResolvableFunctionReference{UnresolvedName{Name($1)}}) }
| OVERLAY '(' overlay_list ')'
  {
    $$.val = &FuncExpr{Func: wrapFunction($1), Exprs: $3.exprs()}
  }
| OVERLAY '(' error { return helpWithFunction(sqllex, ResolvableFunctionReference{UnresolvedName{Name($1)}}) }
| POSITION '(' position_list ')'
  {
    $$.val = &FuncExpr{Func: wrapFunction("STRPOS"), Exprs: $3.exprs()}
  }
| SUBSTRING '(' substr_list ')'
  {
    $$.val = &FuncExpr{Func: wrapFunction($1), Exprs: $3.exprs()}
  }
| SUBSTRING '(' error { return helpWithFunction(sqllex, ResolvableFunctionReference{UnresolvedName{Name($1)}}) }
| TREAT '(' a_expr AS typename ')' { return unimplemented(sqllex, "treat") }
| TRIM '(' BOTH trim_list ')'
  {
    $$.val = &FuncExpr{Func: wrapFunction("BTRIM"), Exprs: $4.exprs()}
  }
| TRIM '(' LEADING trim_list ')'
  {
    $$.val = &FuncExpr{Func: wrapFunction("LTRIM"), Exprs: $4.exprs()}
  }
| TRIM '(' TRAILING trim_list ')'
  {
    $$.val = &FuncExpr{Func: wrapFunction("RTRIM"), Exprs: $4.exprs()}
  }
| TRIM '(' trim_list ')'
  {
    $$.val = &FuncExpr{Func: wrapFunction("BTRIM"), Exprs: $3.exprs()}
  }
| IF '(' a_expr ',' a_expr ',' a_expr ')'
  {
    $$.val = &IfExpr{Cond: $3.expr(), True: $5.expr(), Else: $7.expr()}
  }
| NULLIF '(' a_expr ',' a_expr ')'
  {
    $$.val = &NullIfExpr{Expr1: $3.expr(), Expr2: $5.expr()}
  }
| IFNULL '(' a_expr ',' a_expr ')'
  {
    $$.val = &CoalesceExpr{Name: "IFNULL", Exprs: Exprs{$3.expr(), $5.expr()}}
  }
| COALESCE '(' expr_list ')'
  {
    $$.val = &CoalesceExpr{Name: "COALESCE", Exprs: $3.exprs()}
  }
| GREATEST '(' expr_list ')'
  {
    $$.val = &FuncExpr{Func: wrapFunction($1), Exprs: $3.exprs()}
  }
| GREATEST '(' error { return helpWithFunction(sqllex, ResolvableFunctionReference{UnresolvedName{Name($1)}}) }
| LEAST '(' expr_list ')'
  {
    $$.val = &FuncExpr{Func: wrapFunction($1), Exprs: $3.exprs()}
  }
| LEAST '(' error { return helpWithFunction(sqllex, ResolvableFunctionReference{UnresolvedName{Name($1)}}) }

// Aggregate decoration clauses
within_group_clause:
WITHIN GROUP '(' sort_clause ')' { return unimplemented(sqllex, "within group") }
| /* EMPTY */ {}

filter_clause:
  FILTER '(' WHERE a_expr ')'
  {
    $$.val = $4.expr()
  }
| /* EMPTY */
  {
    $$.val = Expr(nil)
  }

// Window Definitions
window_clause:
  WINDOW window_definition_list
  {
    $$.val = $2.window()
  }
| /* EMPTY */
  {
    $$.val = Window(nil)
  }

window_definition_list:
  window_definition
  {
    $$.val = Window{$1.windowDef()}
  }
| window_definition_list ',' window_definition
  {
    $$.val = append($1.window(), $3.windowDef())
  }

window_definition:
  name AS window_specification
  {
    n := $3.windowDef()
    n.Name = Name($1)
    $$.val = n
  }

over_clause:
  OVER window_specification
  {
    $$.val = $2.windowDef()
  }
| OVER name
  {
    $$.val = &WindowDef{Name: Name($2)}
  }
| /* EMPTY */
  {
    $$.val = (*WindowDef)(nil)
  }

window_specification:
  '(' opt_existing_window_name opt_partition_clause
    opt_sort_clause opt_frame_clause ')'
  {
    $$.val = &WindowDef{
      RefName: Name($2),
      Partitions: $3.exprs(),
      OrderBy: $4.orderBy(),
    }
  }

// If we see PARTITION, RANGE, or ROWS as the first token after the '(' of a
// window_specification, we want the assumption to be that there is no
// existing_window_name; but those keywords are unreserved and so could be
// names. We fix this by making them have the same precedence as IDENT and
// giving the empty production here a slightly higher precedence, so that the
// shift/reduce conflict is resolved in favor of reducing the rule. These
// keywords are thus precluded from being an existing_window_name but are not
// reserved for any other purpose.
opt_existing_window_name:
  name
| /* EMPTY */ %prec CONCAT
  {
    $$ = ""
  }

opt_partition_clause:
  PARTITION BY expr_list
  {
    $$.val = $3.exprs()
  }
| /* EMPTY */
  {
    $$.val = Exprs(nil)
  }

// For frame clauses, we return a WindowDef, but only some fields are used:
// frameOptions, startOffset, and endOffset.
//
// This is only a subset of the full SQL:2008 frame_clause grammar. We don't
// support <window frame exclusion> yet.
opt_frame_clause:
  RANGE frame_extent { return unimplemented(sqllex, "frame range") }
| ROWS frame_extent { return unimplemented(sqllex, "frame rows") }
| /* EMPTY */ {}

frame_extent:
  frame_bound { return unimplemented(sqllex, "frame_extent") }
| BETWEEN frame_bound AND frame_bound { return unimplemented(sqllex, "frame_extent") }

// This is used for both frame start and frame end, with output set up on the
// assumption it's frame start; the frame_extent productions must reject
// invalid cases.
frame_bound:
  UNBOUNDED PRECEDING { return unimplemented(sqllex, "frame_bound") }
| UNBOUNDED FOLLOWING { return unimplemented(sqllex, "frame_bound") }
| CURRENT ROW { return unimplemented(sqllex, "frame_bound") }
| a_expr PRECEDING { return unimplemented(sqllex, "frame_bound") }
| a_expr FOLLOWING { return unimplemented(sqllex, "frame_bound") }

// Supporting nonterminals for expressions.

// Explicit row production.
//
// SQL99 allows an optional ROW keyword, so we can now do single-element rows
// without conflicting with the parenthesized a_expr production. Without the
// ROW keyword, there must be more than one a_expr inside the parens.
row:
  ROW '(' opt_expr_list ')'
  {
    $$.val = &Tuple{Exprs: $3.exprs(), row: true}
  }
| '(' expr_list ',' a_expr ')'
  {
    $$.val = &Tuple{Exprs: append($2.exprs(), $4.expr())}
  }

explicit_row:
  ROW '(' opt_expr_list ')'
  {
    $$.val = &Tuple{Exprs: $3.exprs(), row: true}
  }

implicit_row:
  '(' expr_list ',' a_expr ')'
  {
    $$.val = &Tuple{Exprs: append($2.exprs(), $4.expr())}
  }

sub_type:
  ANY
  {
    $$.val = Any
  }
| SOME
  {
    $$.val = Some
  }
| ALL
  {
    $$.val = All
  }

math_op:
  '+' { $$.val = Plus  }
| '-' { $$.val = Minus }
| '*' { $$.val = Mult  }
| '/' { $$.val = Div   }
| FLOORDIV { $$.val = FloorDiv }
| '%' { $$.val = Mod    }
| '&' { $$.val = Bitand }
| '|' { $$.val = Bitor  }
| '^' { $$.val = Pow }
| '#' { $$.val = Bitxor }
| '<' { $$.val = LT }
| '>' { $$.val = GT }
| '=' { $$.val = EQ }
| LESS_EQUALS    { $$.val = LE }
| GREATER_EQUALS { $$.val = GE }
| NOT_EQUALS     { $$.val = NE }

subquery_op:
  math_op
| LIKE         { $$.val = Like     }
| NOT_LA LIKE  { $$.val = NotLike  }
| ILIKE        { $$.val = ILike    }
| NOT_LA ILIKE { $$.val = NotILike }
  // cannot put SIMILAR TO here, because SIMILAR TO is a hack.
  // the regular expression is preprocessed by a function (similar_escape),
  // and the ~ operator for posix regular expressions is used.
  //        x SIMILAR TO y     ->    x ~ similar_escape(y)
  // this transformation is made on the fly by the parser upwards.
  // however the SubLink structure which handles any/some/all stuff
  // is not ready for such a thing.

opt_expr_list:
  expr_list
| /* EMPTY */
  {
    $$.val = Exprs(nil)
  }

expr_list:
  a_expr
  {
    $$.val = Exprs{$1.expr()}
  }
| expr_list ',' a_expr
  {
    $$.val = append($1.exprs(), $3.expr())
  }

type_list:
  typename
  {
    $$.val = []coltypes.T{$1.colType()}
  }
| type_list ',' typename
  {
    $$.val = append($1.colTypes(), $3.colType())
  }

array_expr:
  '[' opt_expr_list ']'
  {
    $$.val = &Array{Exprs: $2.exprs()}
  }
| '[' array_expr_list ']'
  {
    $$.val = &Array{Exprs: $2.exprs()}
  }

array_expr_list:
  array_expr
  {
    $$.val = Exprs{$1.expr()}
  }
| array_expr_list ',' array_expr
  {
    $$.val = append($1.exprs(), $3.expr())
  }

extract_list:
  extract_arg FROM a_expr
  {
    $$.val = Exprs{&StrVal{s: $1}, $3.expr()}
  }
| expr_list
  {
    $$.val = $1.exprs()
  }

// TODO(vivek): Narrow down to just IDENT once the other
// terms are not keywords.
extract_arg:
  IDENT
| YEAR
| MONTH
| DAY
| HOUR
| MINUTE
| SECOND

// OVERLAY() arguments
// SQL99 defines the OVERLAY() function:
//   - overlay(text placing text from int for int)
//   - overlay(text placing text from int)
// and similarly for binary strings
overlay_list:
  a_expr overlay_placing substr_from substr_for
  {
    $$.val = Exprs{$1.expr(), $2.expr(), $3.expr(), $4.expr()}
  }
| a_expr overlay_placing substr_from
  {
    $$.val = Exprs{$1.expr(), $2.expr(), $3.expr()}
  }
| expr_list
  {
    $$.val = $1.exprs()
  }

overlay_placing:
  PLACING a_expr
  {
    $$.val = $2.expr()
  }

// position_list uses b_expr not a_expr to avoid conflict with general IN
position_list:
  b_expr IN b_expr
  {
    $$.val = Exprs{$3.expr(), $1.expr()}
  }
| /* EMPTY */
  {
    $$.val = Exprs(nil)
  }

// SUBSTRING() arguments
// SQL9x defines a specific syntax for arguments to SUBSTRING():
//   - substring(text from int for int)
//   - substring(text from int) get entire string from starting point "int"
//   - substring(text for int) get first "int" characters of string
//   - substring(text from pattern) get entire string matching pattern
//   - substring(text from pattern for escape) same with specified escape char
// We also want to support generic substring functions which accept
// the usual generic list of arguments. So we will accept both styles
// here, and convert the SQL9x style to the generic list for further
// processing. - thomas 2000-11-28
substr_list:
  a_expr substr_from substr_for
  {
    $$.val = Exprs{$1.expr(), $2.expr(), $3.expr()}
  }
| a_expr substr_for substr_from
  {
    $$.val = Exprs{$1.expr(), $3.expr(), $2.expr()}
  }
| a_expr substr_from
  {
    $$.val = Exprs{$1.expr(), $2.expr()}
  }
| a_expr substr_for
  {
    $$.val = Exprs{$1.expr(), NewDInt(1), $2.expr()}
  }
| opt_expr_list
  {
    $$.val = $1.exprs()
  }

substr_from:
  FROM a_expr
  {
    $$.val = $2.expr()
  }

substr_for:
  FOR a_expr
  {
    $$.val = $2.expr()
  }

trim_list:
  a_expr FROM expr_list
  {
    $$.val = append($3.exprs(), $1.expr())
  }
| FROM expr_list
  {
    $$.val = $2.exprs()
  }
| expr_list
  {
    $$.val = $1.exprs()
  }

in_expr:
  select_with_parens
  {
    $$.val = &Subquery{Select: $1.selectStmt()}
  }
| '(' expr_list ')'
  {
    $$.val = &Tuple{Exprs: $2.exprs()}
  }

// Define SQL-style CASE clause.
// - Full specification
//      CASE WHEN a = b THEN c ... ELSE d END
// - Implicit argument
//      CASE a WHEN b THEN c ... ELSE d END
case_expr:
  CASE case_arg when_clause_list case_default END
  {
    $$.val = &CaseExpr{Expr: $2.expr(), Whens: $3.whens(), Else: $4.expr()}
  }

when_clause_list:
  // There must be at least one
  when_clause
  {
    $$.val = []*When{$1.when()}
  }
| when_clause_list when_clause
  {
    $$.val = append($1.whens(), $2.when())
  }

when_clause:
  WHEN a_expr THEN a_expr
  {
    $$.val = &When{Cond: $2.expr(), Val: $4.expr()}
  }

case_default:
  ELSE a_expr
  {
    $$.val = $2.expr()
  }
| /* EMPTY */
  {
    $$.val = Expr(nil)
  }

case_arg:
  a_expr
| /* EMPTY */
  {
    $$.val = Expr(nil)
  }

array_subscript:
  '[' a_expr ']'
  {
    $$.val = &ArraySubscript{Begin: $2.expr()}
  }
| '[' opt_slice_bound ':' opt_slice_bound ']'
  {
    $$.val = &ArraySubscript{Begin: $2.expr(), End: $4.expr(), Slice: true}
  }

opt_slice_bound:
  a_expr
| /*EMPTY*/
  {
    $$.val = Expr(nil)
  }

name_indirection:
  '.' unrestricted_name
  {
    $$.val = Name($2)
  }

glob_indirection:
  '.' '*'
  {
    $$.val = UnqualifiedStar{}
  }

name_indirection_elem:
  glob_indirection
  {
    $$.val = $1.namePart()
  }
| name_indirection
  {
    $$.val = $1.namePart()
  }

qname_indirection:
  name_indirection_elem
  {
    $$.val = UnresolvedName{$1.namePart()}
  }
| qname_indirection name_indirection_elem
  {
    $$.val = append($1.unresolvedName(), $2.namePart())
  }

array_subscripts:
  array_subscript
  {
    $$.val = ArraySubscripts{$1.arraySubscript()}
  }
| array_subscripts array_subscript
  {
    $$.val = append($1.arraySubscripts(), $2.arraySubscript())
  }

opt_asymmetric:
  ASYMMETRIC {}
| /* EMPTY */ {}

target_list:
  target_elem
  {
    $$.val = SelectExprs{$1.selExpr()}
  }
| target_list ',' target_elem
  {
    $$.val = append($1.selExprs(), $3.selExpr())
  }

target_elem:
  a_expr AS unrestricted_name
  {
    $$.val = SelectExpr{Expr: $1.expr(), As: UnrestrictedName($3)}
  }
  // We support omitting AS only for column labels that aren't any known
  // keyword. There is an ambiguity against postfix operators: is "a ! b" an
  // infix expression, or a postfix expression and a column label?  We prefer
  // to resolve this as an infix expression, which we accomplish by assigning
  // IDENT a precedence higher than POSTFIXOP.
| a_expr IDENT
  {
    $$.val = SelectExpr{Expr: $1.expr(), As: UnrestrictedName($2)}
  }
| a_expr
  {
    $$.val = SelectExpr{Expr: $1.expr()}
  }
| '*'
  {
    $$.val = starSelectExpr()
  }

// Names and constants.

qualified_name_list:
  qualified_name
  {
    $$.val = UnresolvedNames{$1.unresolvedName()}
  }
| qualified_name_list ',' qualified_name
  {
    $$.val = append($1.unresolvedNames(), $3.unresolvedName())
  }

table_name_with_index_list:
  table_name_with_index
  {
    $$.val = TableNameWithIndexList{$1.newTableWithIdx()}
  }
| table_name_with_index_list ',' table_name_with_index
  {
    $$.val = append($1.newTableWithIdxList(), $3.newTableWithIdx())
  }

table_pattern_list:
  table_pattern
  {
    $$.val = TablePatterns{$1.unresolvedName()}
  }
| table_pattern_list ',' table_pattern
  {
    $$.val = append($1.tablePatterns(), $3.unresolvedName())
  }

// The production for a qualified relation name has to exactly match the
// production for a qualified func_name, because in a FROM clause we cannot
// tell which we are parsing until we see what comes after it ('(' for a
// func_name, something else for a relation). Therefore we allow 'indirection'
// which may contain subscripts, and reject that case in the C code.
qualified_name:
  name
  {
    $$.val = UnresolvedName{Name($1)}
  }
| name qname_indirection
  {
    $$.val = append(UnresolvedName{Name($1)}, $2.unresolvedName()...)
  }

table_name_with_index:
  qualified_name '@' unrestricted_name
  {
    $$.val = TableNameWithIndex{Table: $1.normalizableTableName(), Index: UnrestrictedName($3)}
  }
| qualified_name
  {
    // This case allows specifying just an index name (potentially schema-qualified).
    // We temporarily store the index name in Table (see TableNameWithIndex).
    $$.val = TableNameWithIndex{Table: $1.normalizableTableName(), SearchTable: true}
  }

// table_pattern accepts:
// <database>.<table>
// <database>.*
// <table>
// *
table_pattern:
  name
  {
    $$.val = UnresolvedName{Name($1)}
  }
| '*'
  {
    $$.val = UnresolvedName{UnqualifiedStar{}}
  }
| name name_indirection
  {
    $$.val = UnresolvedName{Name($1), $2.namePart()}
  }
| name glob_indirection
  {
    $$.val = UnresolvedName{Name($1), $2.namePart()}
  }

name_list:
  name
  {
    $$.val = NameList{Name($1)}
  }
| name_list ',' name
  {
    $$.val = append($1.nameList(), Name($3))
  }

opt_name_list:
  '(' name_list ')'
  {
    $$.val = $2.nameList()
  }
| /* EMPTY */ {}

// The production for a qualified func_name has to exactly match the production
// for a qualified name, because we cannot tell which we are parsing until
// we see what comes after it ('(' or SCONST for a func_name, anything else for
// a name). Therefore we allow 'indirection' which may contain
// subscripts, and reject that case in the C code. (If we ever implement
// SQL99-like methods, such syntax may actually become legal!)
func_name:
  type_function_name
  {
    $$.val = UnresolvedName{Name($1)}
  }
| name qname_indirection
  {
    $$.val = append(UnresolvedName{Name($1)}, $2.unresolvedName()...)
  }

// Constants
a_expr_const:
  ICONST
  {
    $$.val = $1.numVal()
  }
| FCONST
  {
    $$.val = $1.numVal()
  }
| SCONST
  {
    $$.val = &StrVal{s: $1}
  }
| BCONST
  {
    $$.val = &StrVal{s: $1, bytesEsc: true}
  }
| func_name '(' expr_list opt_sort_clause ')' SCONST { return unimplemented(sqllex, "func const") }
| const_typename SCONST
  {
    $$.val = &CastExpr{Expr: &StrVal{s: $2}, Type: $1.colType(), syntaxMode: castPrepend}
  }
| interval
  {
    $$.val = $1.expr()
  }
| const_interval '(' ICONST ')' SCONST { return unimplemented(sqllex, "expr_const const_interval") }
| TRUE
  {
    $$.val = MakeDBool(true)
  }
| FALSE
  {
    $$.val = MakeDBool(false)
  }
| NULL
  {
    $$.val = DNull
  }

signed_iconst:
  ICONST
| '+' ICONST
  {
    $$.val = $2.numVal()
  }
| '-' ICONST
  {
    $$.val = &NumVal{Value: constant.UnaryOp(token.SUB, $2.numVal().Value, 0)}
  }

interval:
  const_interval SCONST opt_interval
  {
    // We don't carry opt_interval information into the column type, so we need
    // to parse the interval directly.
    var err error
    var d Datum
    if $3.val == nil {
      d, err = ParseDInterval($2)
    } else {
      d, err = ParseDIntervalWithField($2, $3.durationField())
    }
    if err != nil {
      sqllex.Error(err.Error())
      return 1
    }
    $$.val = d
  }

// Name classification hierarchy.
//
// IDENT is the lexeme returned by the lexer for identifiers that match no
// known keyword. In most cases, we can accept certain keywords as names, not
// only IDENTs. We prefer to accept as many such keywords as possible to
// minimize the impact of "reserved words" on programmers. So, we divide names
// into several possible classes. The classification is chosen in part to make
// keywords acceptable as names wherever possible.

// General name --- names that can be column, table, etc names.
name:
  IDENT
| unreserved_keyword
| col_name_keyword

opt_name:
  name
| /* EMPTY */
  {
    $$ = ""
  }

opt_name_parens:
  '(' name ')'
  {
    $$ = $2
  }
| /* EMPTY */
  {
    $$ = ""
  }

// Type/function identifier --- names that can be type or function names.
type_function_name:
  IDENT
| unreserved_keyword
| type_func_name_keyword

// Any not-fully-reserved word --- these names can be, eg, variable names.
non_reserved_word:
  IDENT
| unreserved_keyword
| col_name_keyword
| type_func_name_keyword

// Unrestricted name --- allowable names when there is no ambiguity with even
// reserved keywords, like in "AS" clauses. This presently includes *all*
// Postgres keywords.
unrestricted_name:
  IDENT
| unreserved_keyword
| col_name_keyword
| type_func_name_keyword
| reserved_keyword

// Keyword category lists. Generally, every keyword present in the Postgres
// grammar should appear in exactly one of these lists.
//
// Put a new keyword into the first list that it can go into without causing
// shift or reduce conflicts. The earlier lists define "less reserved"
// categories of keywords.
//
// "Unreserved" keywords --- available for use as any kind of name.
unreserved_keyword:
  ACTION
| ADD
| ALTER
| AT
| BACKUP
| BEGIN
| BLOB
| BY
| CANCEL
| CASCADE
| CLUSTER
| COLUMNS
| COMMIT
| COMMITTED
| CONFLICT
| CONFIGURATION
| CONFIGURATIONS
| CONFIGURE
| CONSTRAINTS
| COPY
| COVERING
| CSV
| CUBE
| CURRENT
| CYCLE
| DATA
| DATABASE
| DATABASES
| DAY
| DEALLOCATE
| DELETE
| DISCARD
| DOUBLE
| DROP
| ENCODING
| EXECUTE
| EXPERIMENTAL
| EXPERIMENTAL_FINGERPRINTS
| EXPLAIN
| FILTER
| FIRST
| FOLLOWING
| FORCE_INDEX
| GRANTS
| HIGH
| HOUR
| IMPORT
| INCREMENTAL
| INDEXES
| INSERT
| INT2VECTOR
| INTERLEAVE
| ISOLATION
| JOB
| JOBS
| KEY
| KEYS
| KV
| LC_COLLATE
| LC_CTYPE
| LESS
| LEVEL
| LIST
| LOCAL
| LOW
| MATCH
| MINUTE
| MONTH
| NAMES
| NAN
| NEXT
| NO
| NORMAL
| NO_INDEX_JOIN
| NULLS
| OF
| OFF
| OID
| OPTIONS
| ORDINALITY
| OVER
| PARENT
| PARTIAL
| PARTITION
| PASSWORD
| PAUSE
| PHYSICAL
| PLANS
| PRECEDING
| PREPARE
| PRIORITY
| QUERIES
| QUERY
| RANGE
| READ
| RECURSIVE
| REF
| REGCLASS
| REGPROC
| REGPROCEDURE
| REGNAMESPACE
| REGTYPE
| RELEASE
| RENAME
| REPEATABLE
| RESET
| RESTORE
| RESTRICT
| RESUME
| REVOKE
| ROLLBACK
| ROLLUP
| ROWS
| SETTING
| SETTINGS
| STATUS
| SAVEPOINT
| SCATTER
| SCRUB
| SEARCH
| SECOND
| SERIALIZABLE
| SEQUENCES
| SESSION
| SESSIONS
| SET
| SHOW
| SIMPLE
| SNAPSHOT
| SQL
| START
| STDIN
| STORE
| STORING
| STRICT
| SPLIT
| SYSTEM
| TABLES
| TEMP
| TEMPLATE
| TEMPORARY
| TESTING_RANGES
| TESTING_RELOCATE
| TEXT
| THAN
| TRACE
| TRANSACTION
| TRUNCATE
| TYPE
| UNBOUNDED
| UNCOMMITTED
| UNKNOWN
| UPDATE
| UPSERT
| USE
| USERS
| VALID
| VALIDATE
| VALUE
| VARYING
| WITHIN
| WITHOUT
| WRITE
| YEAR
| ZONE

// Column identifier --- keywords that can be column, table, etc names.
//
// Many of these keywords will in fact be recognized as type or function names
// too; but they have special productions for the purpose, and so can't be
// treated as "generic" type or function names.
//
// The type names appearing here are not usable as function names because they
// can be followed by '(' in typename productions, which looks too much like a
// function call for an LR(1) parser.
col_name_keyword:
  ANNOTATE_TYPE
| BETWEEN
| BIGINT
| BIGSERIAL
| BIT
| BOOL
| BOOLEAN
| BYTEA
| BYTES
| CHAR
| CHARACTER
| CHARACTERISTICS
| COALESCE
| DATE
| DEC
| DECIMAL
| EXISTS
| EXTRACT
| EXTRACT_DURATION
| FLOAT
| FLOAT4
| FLOAT8
| GREATEST
| GROUPING
| IF
| IFNULL
| INET
| INT
| INT2
| INT4
| INT8
| INT64
| INTEGER
| INTERVAL
| JSON
| JSONB
| LEAST
| NAME
| NULLIF
| NUMERIC
| OUT
| OVERLAY
| POSITION
| PRECISION
| REAL
| ROW
| SERIAL
| SMALLINT
| SMALLSERIAL
| STRING
| SUBSTRING
| TIME
| TIMESTAMP
| TIMESTAMPTZ
| TREAT
| TRIM
| UUID
| VALUES
| VARCHAR

// Type/function identifier --- keywords that can be type or function names.
//
// Most of these are keywords that are used as operators in expressions; in
// general such keywords can't be column names because they would be ambiguous
// with variables, but they are unambiguous as function identifiers.
//
// Do not include POSITION, SUBSTRING, etc here since they have explicit
// productions in a_expr to support the goofy SQL9x argument syntax.
// - thomas 2000-11-28
//
// TODO(dan): see if we can move MAXVALUE to a less restricted list
type_func_name_keyword:
  COLLATION
| CROSS
| FAMILY
| FULL
| INNER
| ILIKE
| IS
| JOIN
| LEFT
| LIKE
| MAXVALUE
| NATURAL
| OUTER
| OVERLAPS
| RIGHT
| SIMILAR

// Reserved keyword --- these keywords are usable only as a unrestricted_name.
//
// Keywords appear here if they could not be distinguished from variable, type,
// or function names in some contexts. Don't put things here unless forced to.
reserved_keyword:
  ALL
| ANALYSE
| ANALYZE
| AND
| ANY
| ARRAY
| AS
| ASC
| ASYMMETRIC
| BOTH
| CASE
| CAST
| CHECK
| COLLATE
| COLUMN
| CONSTRAINT
| CREATE
| CURRENT_CATALOG
| CURRENT_DATE
| CURRENT_ROLE
| CURRENT_SCHEMA
| CURRENT_TIME
| CURRENT_TIMESTAMP
| CURRENT_USER
| DEFAULT
| DEFERRABLE
| DESC
| DISTINCT
| DO
| ELSE
| END
| EXCEPT
| FALSE
| FETCH
| FOR
| FOREIGN
| FROM
| GRANT
| GROUP
| HAVING
| IN
| INDEX
| INITIALLY
| INTERSECT
| INTO
| LATERAL
| LEADING
| LIMIT
| LOCALTIME
| LOCALTIMESTAMP
| NOT
| NOTHING
| NULL
| OFFSET
| ON
| ONLY
| OR
| ORDER
| PLACING
| PRIMARY
| REFERENCES
| RETURNING
| SELECT
| SESSION_USER
| SOME
| SYMMETRIC
| TABLE
| THEN
| TO
| TRAILING
| TRUE
| UNION
| UNIQUE
| USER
| USING
| VARIADIC
| VIEW
| WHEN
| WHERE
| WINDOW
| WITH

%%
