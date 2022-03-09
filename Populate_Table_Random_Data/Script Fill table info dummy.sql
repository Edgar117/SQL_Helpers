IF OBJECT_ID (N'dbo.PopulateTableRandomData') IS NOT NULL     DROP PROC dbo.PopulateTableRandomData
GO
CREATE PROC [dbo].[PopulateTableRandomData]
-------WE BEGIN WITH IDENTIFYING WHETHER THE KEY IS an identity key or is calculable
@TableName VARCHAR(50)='Customers',----TABLE NAME
@Schema VARCHAR(10)='dbo',         ----SCHEMA TABLE
@TOP INT=1000000,                  --- NUMBER OF RECORDS TO INSERT
@IgnoringFields NVARCHAR(MAX)=''   --- Fields that you do not want to be considered
AS
BEGIN
SET NOCOUNT ON;
------GENERAL VARIABLES
DECLARE @PrimaryKey VARCHAR(100)
DECLARE @IsIdentity BIT
DECLARE @PrepareSQLStament NVARCHAR(MAX)

--GET the primary key if exists
SELECT @PrimaryKey=COLUMN_NAME
FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
WHERE OBJECTPROPERTY(OBJECT_ID(CONSTRAINT_SCHEMA + '.' + QUOTENAME(CONSTRAINT_NAME)), 'IsPrimaryKey') = 1
AND TABLE_NAME = @TableName AND TABLE_SCHEMA = @Schema

SET @PrimaryKey=ISNULL(@PrimaryKey,'');

--Check if the primary key is of type identity to know if it is considered in the insert or not
SELECT @IsIdentity= c.is_identity 
FROM sys.columns c
    left join sys.index_columns ic on  c.column_id = ic.column_id and c.object_id = ic.object_id
    left JOIN sys.indexes i ON i.index_id = ic.index_id and c.object_id = i.object_id  and i.is_primary_key= 1
    left JOIN sys.identity_columns idc ON idc.object_id = c.object_id AND idc.column_id = c.column_id
WHERE i.is_primary_key = 1  
AND object_name(c.object_id)=@TableName AND c.name=@PrimaryKey

--Column insertion preparation
SELECT @PrepareSQLStament=COALESCE( @PrepareSQLStament +',','')+ 
--VERIFICATION OF DATA TYPES
--TYPES 'TINYINT', 'BIGINT', 'INT', 'SMALLMONEY', 'MONEY', 'SMALLINT'
CASE WHEN T.name IN ('TINYINT', 'BIGINT', 'INT', 'SMALLMONEY', 'MONEY', 'SMALLINT') THEN 
'CAST( CAST(ROUND(RAND(CHECKSUM(NEWID()))*'+'1'+REPLICATE('0',C.[Precision]-1)+'+1'+REPLICATE('0',C.[Precision]-1)+',0) AS BIGINT) AS VARCHAR('+CAST(C.[Precision] AS VARCHAR(100))+'))'
--TYPES 'CHAR', 'VARCHAR', 'NCHAR', 'NVARCHAR', 'TEXT', 'NTEXT'
 WHEN T.NAME IN ('CHAR', 'VARCHAR', 'NCHAR', 'NVARCHAR') THEN 
 'CAST(REPLACE(NEWID(),''-'','''') AS '+T.NAME +'('+ CASE WHEN C.max_length=-1 THEN 'MAX' ELSE CASE WHEN T.name='NVARCHAR' THEN CAST(C.max_length/2 AS VARCHAR(100)) ELSE CAST(C.max_length AS VARCHAR(100)) END END +'))'
 --TYPE BIT
 WHEN T.NAME ='BIT' THEN 
 '(SELECT TOP 1 Bit_Field FROM @Bit_Table ORDER BY NEWID())'
 --TYPES DATETIME
 WHEN T.name IN ('datetime','DATE') THEN  
 'DATEADD(HOUR,CAST(RAND(CHECKSUM(NEWID())) * 19999 as INT) + 1 ,''2006-01-01'')'
 --TYPES DECIMAL and NUMERIC
WHEN T.NAME IN ('decimal','NUMERIC') THEN 
'CAST( CAST(ROUND(RAND(CHECKSUM(NEWID()))*'+'1'+REPLICATE('0',C.[max_length]-1)+'+1'+REPLICATE('0',C.[max_length]-1)+',0) AS BIGINT) AS VARCHAR('+CAST(C.[max_length] AS VARCHAR(100))+'))' 
+
'+''.''+'
+
CASE WHEN C.scale>0 THEN
'CAST( CAST(ROUND(RAND(CHECKSUM(NEWID()))*'+'1'+REPLICATE('0',C.[scale]-1)+'+1'+REPLICATE('0',C.[scale]-1)+',0) AS BIGINT) AS VARCHAR('+CAST(C.[scale] AS VARCHAR(100))+'))' 
ELSE 
'''0'''
END
 --TYPE uniqueidentifier
 WHEN T.name='uniqueidentifier' THEN 'NEWID()'
 --TYPES 'VARBINARY', 'BINARY'
 WHEN T.name IN ('VARBINARY', 'BINARY')THEN '''0x'''
  --TYPES FLOAT
 WHEN T.name='float' THEN 
 'CAST( CAST(ROUND(RAND(CHECKSUM(NEWID()))*'+'1'+REPLICATE('0',C.[max_length]-1)+'+1'+REPLICATE('0',C.[max_length]-1)+',0) AS BIGINT) AS VARCHAR('+CAST(C.[max_length] AS VARCHAR(100))+'))'
--TYPES TIME
 WHEN T.name='TIME' THEN 'CAST(DATEADD(HOUR,CAST(RAND(CHECKSUM(NEWID())) * 19999 as INT) + 1 ,''2006-01-01'') AS TIME)' END --+')'

+CHAR(13) + CHAR(10)
FROM
 sys.tables O
  INNER JOIN sys.Columns C
    ON O.object_id = C.object_id
  INNER JOIN sys.Types T
    ON C.system_type_id = T.system_type_id
    AND C.system_type_id = T.user_type_id
	 WHERE O.name=@TableName AND C.name <>@PrimaryKey
     AND C.name NOT IN (SELECT VALUE FROM String_split(@IgnoringFields,','))--IGNORING FIELDS



--MAXIMUM VALUE OF ID IF THE PRIMARY KEY IS OF CALCULABLE TYPE
DECLARE @retval int =0;  
DECLARE @sSQL nvarchar(500);
DECLARE @ParmDefinition nvarchar(500);


SELECT @sSQL = N'SELECT  @retvalOUT = ISNULL(MAX('+@PrimaryKey+'),0)+1 FROM ' + QUOTENAME(@Schema)+'.'+QUOTENAME(@TableName); 
SET @ParmDefinition = N'@retvalOUT int OUTPUT';

IF @PrimaryKey<>''
EXEC sp_executesql @sSQL, @ParmDefinition, @retvalOUT=@retval OUTPUT;

-------HELPER BIT TO FILL DUMMY DATA

DECLARE @Helper_Bit NVARCHAR(MAX)='
DECLARE  @Bit_Table TABLE(Bit_Field BIT)
INSERT INTO @Bit_Table VALUES (1)
INSERT INTO @Bit_Table VALUES (0)
'


--INSERT STAMENT
DECLARE @InsertStament NVARCHAR(MAX)
SELECT
@InsertStament=COALESCE( @InsertStament +',','')+ C.name
FROM
 sys.tables O
  INNER JOIN sys.Columns C
    ON O.object_id = C.object_id
  INNER JOIN sys.Types T
    ON C.system_type_id = T.system_type_id
    AND C.system_type_id = T.user_type_id
	 WHERE O.name=@TableName AND C.name <>@PrimaryKey
     AND C.name NOT IN (SELECT VALUE FROM String_split(@IgnoringFields,','))

------PRIMARY KEY
SET @InsertStament=CASE WHEN @IsIdentity=0 THEN @PrimaryKey+' , ' ELSE '' END+@InsertStament
--INSERT INTO 
SET @InsertStament=CONCAT('INSERT INTO',' ',QUOTENAME(@Schema),'.',QUOTENAME(@TableName),' ','(',@InsertStament,')')
-----FINAL VARIABLE 
DECLARE @FinalStament NVARCHAR(MAX)='
'+@Helper_Bit+'
--Llenamos un millon de datos
;WITH L0 AS (SELECT 1 c FROM(SELECT 1 UNION ALL SELECT 1)c(D)),
	  L1 AS (SELECT 1 C FROM L0 CROSS JOIN L0 AS B),
	  L2 AS (SELECT 1 C FROM L1 CROSS JOIN L1 AS B),
	  L3 AS (SELECT 1 C FROM L2 CROSS JOIN L2 AS B),
	  L4 AS (SELECT 1 C FROM L3 CROSS JOIN L3 AS B),
	  L5 AS (SELECT 1 C FROM L4 CROSS JOIN L4 AS B),
	  L6 AS (SELECT 1 C FROM L5 CROSS JOIN L5 AS B) --ENOUGH FOR A MILLION
      ,C_R AS (SELECT ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS Rn FROM L6)
      '+@InsertStament+'
      SELECT TOP('+CAST(@TOP AS VARCHAR(10))+')
      '
      -----Valid type primary key
      +CASE WHEN @IsIdentity=0 THEN '(RN +'+CAST(@retval AS VARCHAR(100))+'), ' ELSE '' END
      +@PrepareSQLStament
      +' FROM C_R'

EXEC sp_executesql @FinalStament

-- --**************************CODE TO SEE THE SQL SENTENCE*************************************************  
-- DECLARE @CurrentEnd BIGINT;   /* Gets the length of the next substring */  
-- DECLARE @offset TINYINT;      /* Get the amount of compensation needed */  
-- SET @FinalStament = replace(  replace(@FinalStament, char(13) + char(10), char(10))   , char(13), char(10))  
--   WHILE LEN(@FinalStament) > 1  
--   BEGIN  
--    IF CHARINDEX(CHAR(10), @FinalStament) between 1 AND 4000  
--    BEGIN  
--        SET @CurrentEnd =  CHARINDEX(char(10), @FinalStament) -1  
--        set @offset = 2  
--    END  
--    ELSE  
--    BEGIN  
--        SET @CurrentEnd = 4000  
--      set @offset = 1  
--    END     
--    PRINT SUBSTRING(@FinalStament, 1, @CurrentEnd)   
--    SET @FinalStament = SUBSTRING(@FinalStament, @CurrentEnd+@offset, LEN(@FinalStament))     
--   END   
    
-- --******************************END CODE TO SEE THE SQL SENTENCE************************************* 

END


