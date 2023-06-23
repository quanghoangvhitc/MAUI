USE FPTPetro_DataeOffice
GO

IF OBJECT_ID('VuThao_Mobile_Select_Data_DanhMuc', 'P') IS NOT NULL DROP PROCEDURE VuThao_Mobile_Select_Data_DanhMuc
GO

CREATE PROCEDURE [dbo].[VuThao_Mobile_Select_Data_DanhMuc]
	@Action VARCHAR(100) = '',
	@UserId VARCHAR(50) = '',
	@Email NVARCHAR(200) = '',
	@CurrentSite VARCHAR(100) = '',
	@Parameters NVARCHAR(MAX) = ''
AS
BEGIN
	SET NOCOUNT ON;

	IF ISNULL(@Action,'') = ''
		RETURN;

	DECLARE @cmd NVARCHAR(MAX) = N''

	IF ISNULL(@Parameters,'') != ''
	BEGIN
		DECLARE @tbl@Parameters TABLE(ParentID INT, [Key] NVARCHAR(100), [Value] NVARCHAR(MAX))
		INSERT INTO @tbl@Parameters 
		SELECT Parent_ID,[Name],StringValue FROM parseJSON(@Parameters) WHERE ISNULL([Name],'-') != '-'
	END

	DECLARE @BeanName VARCHAR(50) = NULL
	DECLARE @KeySetting VARCHAR(100) = NULL
	DECLARE @DBName VARCHAR(150) = (SELECT TOP 1 [VALUE] FROM Settings WHERE [KEY] = 'DBSite')
	DECLARE @Modified DATETIME = NULL
	DECLARE @ModifiedF DATETIME = NULL

	IF (SELECT MAX(ParentID) FROM @tbl@Parameters GROUP BY ParentID) = 1
	BEGIN
		SELECT @BeanName = IIF(ISNULL(BeanName,'') = '', NULL , BeanName)
			, @Modified = IIF(ISNULL(Modified,'') = '', NULL , Modified)
			, @KeySetting = IIF(ISNULL([KeySetting],'') = '', NULL , [KeySetting])
		FROM @tbl@Parameters SRC
		PIVOT(MAX([Value]) FOR [Key] IN (BeanName,Modified,KeySetting)) PIV;
	END

	IF ISNULL(@BeanName,'') = ''
		RETURN;

	IF @Modified IS NOT NULL
		SET @ModifiedF = [dbo].fnFormatDate(@Modified,'YYYY/MM/DD HH:MI:SS');

	IF @BeanName = 'SettingByKey'
	BEGIN
		SET @cmd = N'SELECT TOP 1 [VALUE] FROM ['+@DBName + @CurrentSite +N']..Settings WHERE [KEY] = @KeySetting'
		EXEC sp_executesql @cmd
							, N'@KeySetting VARCHAR(100)'
							, @KeySetting = @KeySetting
		RETURN;
	END

	IF LOWER(@BeanName) = 'beanuser'
	BEGIN
		SET @cmd = N'SELECT ID AS ID_SQL,AccountID,FullName AS Title,AccountName AS [Name],AccountName,ImagePath,Position,Email,Created 
		FROM ['+@DBName + @CurrentSite +N']..PersonalProfile 
		WHERE UserStatus != -1 AND (@ModifiedF IS NULL OR Created > @ModifiedF)'
		EXEC sp_executesql @cmd
							, N'@ModifiedF DATETIME'
							, @ModifiedF = @ModifiedF

		RETURN;
	END
END