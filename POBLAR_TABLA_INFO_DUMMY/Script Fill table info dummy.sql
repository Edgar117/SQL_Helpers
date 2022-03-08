-------COMENZAMOS CON LA IDENTIFICACION DE SI LA LLAVE ES llave identity o es calculable
DECLARE @TableName VARCHAR(50)='Customers',----NOMBRE DE LA TABLA
        @Schema VARCHAR(10)='dbo',         ----ESQUEMA DE LA TABLA
        @TOP INT=1000000,                  --- NÚMERO DE REGISTROS A INSERTAR
        @IgnoringFields NVARCHAR(MAX)=''   --- Campos que no quieres insertar


------VARIABLES GENERALES
DECLARE @PrimaryKey VARCHAR(100)
DECLARE @IsIdentity BIT
DECLARE @PrepareSQLStament NVARCHAR(MAX)

--Obtenemos la llave primaria
SELECT @PrimaryKey=COLUMN_NAME
FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
WHERE OBJECTPROPERTY(OBJECT_ID(CONSTRAINT_SCHEMA + '.' + QUOTENAME(CONSTRAINT_NAME)), 'IsPrimaryKey') = 1
AND TABLE_NAME = @TableName AND TABLE_SCHEMA = @Schema

--Verificiar si la llave primaria es de tipo identity para saber si se considera en el  insert o no
SELECT @IsIdentity= c.is_identity 
FROM sys.columns c
    left join sys.index_columns ic on  c.column_id = ic.column_id and c.object_id = ic.object_id
    left JOIN sys.indexes i ON i.index_id = ic.index_id and c.object_id = i.object_id  and i.is_primary_key= 1
    left JOIN sys.identity_columns idc ON idc.object_id = c.object_id AND idc.column_id = c.column_id
WHERE i.is_primary_key = 1  
AND object_name(c.object_id)=@TableName AND c.name=@PrimaryKey

--Preparación de inserccion de columnas
SELECT @PrepareSQLStament=COALESCE( @PrepareSQLStament +',','')+ 
--VERIFICACIÓN DE LOS TIPOS DE DATOS
--TIPOS 'TINYINT', 'BIGINT', 'INT', 'SMALLMONEY', 'MONEY', 'SMALLINT'
CASE WHEN T.name IN ('TINYINT', 'BIGINT', 'INT', 'SMALLMONEY', 'MONEY', 'SMALLINT') THEN 
'CAST( CAST(ROUND(RAND(CHECKSUM(NEWID()))*'+'1'+REPLICATE('0',C.[Precision]-1)+'+4'+REPLICATE('0',C.[Precision]-1)+',0) AS BIGINT) AS VARCHAR('+CAST(C.[Precision] AS VARCHAR(100))+'))'
--TIPOS 'CHAR', 'VARCHAR', 'NCHAR', 'NVARCHAR', 'TEXT', 'NTEXT'
 WHEN T.NAME IN ('CHAR', 'VARCHAR', 'NCHAR', 'NVARCHAR') THEN 
 'CAST(REPLACE(NEWID(),''-'','''') AS '+T.NAME +'('+ CASE WHEN C.max_length=-1 THEN 'MAX' ELSE CAST(C.max_length AS VARCHAR(100)) END +'))'
 --TIPO BIT
 WHEN T.NAME ='BIT' THEN 
 '(SELECT TOP 1 Bit_Field FROM @Bit_Table ORDER BY NEWID())'
 --TIPO DATETIME
 WHEN T.name IN ('datetime','DATE') THEN  
 'DATEADD(HOUR,CAST(RAND(CHECKSUM(NEWID())) * 19999 as INT) + 1 ,''2006-01-01'')'
 --TIPO DECIMAL
WHEN T.NAME IN ('decimal','NUMERIC') THEN 
'CAST( CAST(ROUND(RAND(CHECKSUM(NEWID()))*'+'1'+REPLICATE('0',C.[max_length]-1)+'+4'+REPLICATE('0',C.[max_length]-1)+',0) AS BIGINT) AS VARCHAR('+CAST(C.[max_length] AS VARCHAR(100))+'))' 
+
'+''.''+'
+
'CAST( CAST(ROUND(RAND(CHECKSUM(NEWID()))*'+'1'+REPLICATE('0',C.[scale]-1)+'+4'+REPLICATE('0',C.[scale]-1)+',0) AS BIGINT) AS VARCHAR('+CAST(C.[scale] AS VARCHAR(100))+'))' 
 --TIPO uniqueidentifier
 WHEN T.name='uniqueidentifier' THEN 'NEWID()'
 --TIPO 'VARBINARY', 'BINARY'
 WHEN T.name IN ('VARBINARY', 'BINARY')THEN '''0x'''
  --TIPO FLOAT
 WHEN T.name='float' THEN 
 'CAST( CAST(ROUND(RAND(CHECKSUM(NEWID()))*'+'1'+REPLICATE('0',C.[max_length]-1)+'+4'+REPLICATE('0',C.[max_length]-1)+',0) AS BIGINT) AS VARCHAR('+CAST(C.[max_length] AS VARCHAR(100))+'))'
--TIPO TIEMPO
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
	 AND T.name NOT IN ('TEXT','NTEXT','IMAGE')--DISCRIMINACIÓN DE CAMPOS
     AND C.name NOT IN (SELECT VALUE FROM String_split(@IgnoringFields,','))



--VALOR MAXIMO DE ID SI LA LLAVE PRIMARIA ES DE TIPO CALCULABLE
DECLARE @retval int   
DECLARE @sSQL nvarchar(500);
DECLARE @ParmDefinition nvarchar(500);


SELECT @sSQL = N'SELECT  @retvalOUT = ISNULL(MAX('+@PrimaryKey+'),0)+1 FROM ' + QUOTENAME(@Schema)+'.'+QUOTENAME(@TableName); 
SET @ParmDefinition = N'@retvalOUT int OUTPUT';

EXEC sp_executesql @sSQL, @ParmDefinition, @retvalOUT=@retval OUTPUT;

-------HELPER DEL BIT

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
	 AND T.name NOT IN ('TEXT','NTEXT','IMAGE')--DISCRIMINACIÓN DE CAMPOS
     AND C.name NOT IN (SELECT VALUE FROM String_split(@IgnoringFields,','))

------LLAVE PRIMARIA
SET @InsertStament=CASE WHEN @IsIdentity=0 THEN @PrimaryKey+' , ' ELSE '' END+@InsertStament
--INSERT INTO 
SET @InsertStament=CONCAT('INSERT INTO',' ',QUOTENAME(@Schema),'.',QUOTENAME(@TableName),' ','(',@InsertStament,')')
-----VARIABLE FinaL 
DECLARE @FinalStament NVARCHAR(MAX)='
'+@Helper_Bit+'
--Llenamos un millon de datos
;WITH L0 AS (SELECT 1 c FROM(SELECT 1 UNION ALL SELECT 1)c(D)),
	  L1 AS (SELECT 1 C FROM L0 CROSS JOIN L0 AS B),
	  L2 AS (SELECT 1 C FROM L1 CROSS JOIN L1 AS B),
	  L3 AS (SELECT 1 C FROM L2 CROSS JOIN L2 AS B),
	  L4 AS (SELECT 1 C FROM L3 CROSS JOIN L3 AS B),
	  L5 AS (SELECT 1 C FROM L4 CROSS JOIN L4 AS B),
	  L6 AS (SELECT 1 C FROM L5 CROSS JOIN L5 AS B) --SUFICIENTE PARA UN MILLON
      ,C_R AS (SELECT ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS Rn FROM L6)
      '+@InsertStament+'
      SELECT TOP('+CAST(@TOP AS VARCHAR(10))+')
      '
      -----Validamos el tipo de Llave Primaria
      +CASE WHEN @IsIdentity=0 THEN '(RN +'+CAST(@retval AS VARCHAR(100))+'), ' ELSE '' END
      +@PrepareSQLStament
      +' FROM C_R'

EXEC (@FinalStament)



