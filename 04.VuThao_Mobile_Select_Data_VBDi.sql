USE Petrolimex_DataeOffice
GO 

IF OBJECT_ID('VuThao_Mobile_Select_Data_VBDi', 'P') IS NOT NULL DROP PROCEDURE VuThao_Mobile_Select_Data_VBDi
GO

CREATE PROCEDURE [dbo].[VuThao_Mobile_Select_Data_VBDi]
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

	DECLARE @tblVBDi TABLE (
			[ID] BIGINT,
			[CreatedByText] NVARCHAR(100),
			[CodeCategoryTitle] NVARCHAR(255),
			[Subject] NVARCHAR(4000),
			[StatusText] NVARCHAR(150),
			[DocumentTitle] NVARCHAR(150),
			[Created] DATETIME,
			[Modified] DATETIME,
			[ImagePath] NVARCHAR(255),
			[Position] NVARCHAR(125)
		)

	DECLARE @DomainUrl VARCHAR(250)
	DECLARE @SiteVBUrl VARCHAR(255)
	DECLARE @DBName VARCHAR(150) = (SELECT TOP 1 [VALUE] FROM Settings WHERE [KEY] = 'DBSite')
	DECLARE @FromDate DATETIME = NULL
	DECLARE @ToDate DATETIME = NULL
	DECLARE @FromDateF DATETIME = NULL
	DECLARE @ToDateF DATETIME = NULL
	DECLARE @FilterText NVARCHAR(MAX) = NULL
	DECLARE @TinhTrang NVARCHAR(MAX) = NULL
	DECLARE @BanLanhDao NVARCHAR(MAX) = NULL
	DECLARE @LIMIT INT = 0, @OFFSET INT = 0, @STATUS INT = 0, @IsCount INT = 0, @ModuleId VARCHAR(50) = NULL

	SET @DomainUrl =(SELECT TOP 1 [VALUE] FROM Settings WHERE [KEY] = 'DomainUrl')
	SET @SiteVBUrl = CONCAT(@DomainUrl,IIF(@CurrentSite = N'', N'', N'/' + @CurrentSite))
	SET @SiteVBUrl = CONCAT(@SiteVBUrl,'/vanban')

	IF (SELECT MAX(ParentID) FROM @tbl@Parameters GROUP BY ParentID) = 1
	BEGIN
		SELECT @LIMIT = Limit, @OFFSET = Offset, @STATUS = Status, @IsCount = IsCount
			, @ModuleId = IIF(ISNULL(ModuleId,'') = '', NULL , ModuleId)
			, @FromDate = IIF(ISNULL(FromDate,'') = '', NULL , FromDate)
			, @ToDate = IIF(ISNULL(ToDate,'') = '', NULL , ToDate)
			, @FilterText = IIF(ISNULL(FilterText,'') = '', NULL , FilterText)
			, @BanLanhDao = IIF(ISNULL(BanLanhDao,'') = '', NULL , BanLanhDao)
			, @TinhTrang = IIF(ISNULL(TinhTrang,'') = '', NULL , TinhTrang)
		FROM @tbl@Parameters SRC
		PIVOT(MAX([Value]) FOR [Key] IN (Limit,Offset,Status,IsCount,ModuleId,FromDate,ToDate,FilterText,BanLanhDao,TinhTrang)) PIV;
	END

	IF @FromDate IS NOT NULL
		SET @FromDateF = [dbo].fnFormatDate(@FromDate,'YYYY/MM/DD HH:MI:SS');

	IF @ToDate IS NOT NULL
	BEGIN
		SET @ToDate = CONVERT(VARCHAR,@ToDate,111) + ' 23:59:59'
		SET @ToDateF = [dbo].fnFormatDate(@ToDate,'YYYY/MM/DD HH:MI:SS');
	END

	DECLARE @IsAdmin BIT = 0

	SET @cmd = N'SET @IsAdmin = ISNULL((SELECT TOP 1 1 FROM [' + @DBName + @CurrentSite + N']..[Group] G
		WHERE G.Title = N''Admin''
		AND EXISTS(SELECT TOP 1 1 FROM [' + @DBName + @CurrentSite + N']..UserInGroup UG WHERE UG.GroupId = G.ID AND UG.UserId = @UserId)
		),0)'

	EXECUTE sp_executesql   @cmd,
							N'@UserId VARCHAR(50),@IsAdmin BIT OUT ',
							@UserId = @UserId,@IsAdmin = @IsAdmin OUT

	DECLARE @CodeTB TABLE(ID bigint)
	DECLARE @sCodeTB NVARCHAR(MAX)

	IF ISNULL(@IsAdmin, 0) = 0
	BEGIN
		SET @cmd = N'
			DECLARE @UserTB TABLE(ID uniqueidentifier)
			INSERT INTO @UserTB ([ID]) VALUES(@UserId)
			INSERT INTO @UserTB SELECT [GroupId] FROM [' + @DBName + N'].[dbo].[UserInGroup] WITH (NOLOCK) WHERE [UserId] = @UserId

			DECLARE @UserCount int = (SELECT COUNT(ID) FROM @UserTB)

			SELECT CodeItemId
			FROM [' + @DBName + N']..CodeItemUser CIU (NOLOCK)
			WHERE 
			(
				(@UserCount <= 15 AND CIU.UserId IN (SELECT ID FROM @UserTB)) OR
				(@UserCount > 15 AND EXISTS(SELECT TOP 1 1 FROM @UserTB U WHERE U.ID = CIU.UserId))
			)
			ORDER BY CIU.CodeItemId DESC
		'
		INSERT INTO @CodeTB
		EXECUTE sp_executesql @cmd,
			N'@UserId VARCHAR(50),@IsAdmin BIT OUT ',
			@UserId = @UserId,@IsAdmin = @IsAdmin OUT

		
		SELECT @sCodeTB = STUFF((
					SELECT ',' + CAST(ID AS NVARCHAR)
					FROM @CodeTB
					FOR XML PATH('')
					), 1, 1, '')
		FROM @CodeTB
	END
	
	IF @Action = 'VBDiChoPheDuyet' OR @Action = 'VBDiDaPheDuyet' OR @Action = 'VBDiTatCa'
	BEGIN
		SET @cmd = N'SELECT VBDi.[ID],PP.FullName,CC.Title,VBDi.[Subject]
							,(CASE WHEN VBDi.[Status] < 0 THEN N''Bị huỷ''
								WHEN VBDi.[Status] = 0 THEN N''Đang soạn''
								WHEN VBDi.[Status] = 4 THEN N''Từ chối''
								WHEN VBDi.[Status] = 10 THEN N''Đã phê duyệt''
								WHEN VBDi.[Status] = 11 THEN N''Chờ phát hành''
								WHEN VBDi.[Status] = 12 THEN N''Đã phát hành''
								ELSE VBDi.StatusText END)
							,VBDi.[DocumentTitle]
							,VBDi.[Created],VBDi.[Modified]
							, PP.ImagePath, PP.Position
					FROM ['+@DBName + @CurrentSite +N']..CodeItem VBDi (NOLOCK)
					LEFT JOIN ['+@DBName + @CurrentSite +N']..[CodeCategory] CC (NOLOCK) ON CC.ID = VBDi.CodeCategoryId
					LEFT JOIN ['+@DBName + @CurrentSite +N']..PersonalProfile PP (NOLOCK) ON PP.ID = VBDi.CreatedBy
					WHERE VBDi.[Status] > -1 AND
							(
								@IsAdmin = 1 OR 
								VBDi.CreatedBy = @UserId OR	
								EXISTS(SELECT 1 FROM (SELECT Item FROM dbo.Split(@sCodeTB,'','')) T WHERE T.Item = VBDi.ID)
							)
					'
		IF @Action != 'VBDiTatCa'
		BEGIN
			IF @Action = 'VBDiChoPheDuyet'
			BEGIN
				SET @cmd = @cmd +  N' AND ( VBDi.[StatusText] NOT IN (N''Soạn thảo'',N''Phê duyệt'') AND VBDi.[Status] NOT IN (11,12) )'
			END

			IF @Action = 'VBDiDaPheDuyet'
			BEGIN
				SET @cmd = @cmd +  N' AND ( VBDi.[StatusText] IN (N''Phê duyệt'') OR VBDi.[Status] IN (11,12))'
			END
		END

		IF @FromDateF IS NOT NULL AND @ToDateF IS NOT NULL
			SET @cmd = @cmd + N' AND VBDi.Created BETWEEN @FromDateF AND @ToDateF'

		IF @FilterText IS NOT NULL
			SET @cmd = @cmd + N' AND (VBDi.[Subject] LIKE N''%' + @FilterText + '%'' OR VBDi.[DocumentTitle] LIKE N''%' + @FilterText + '%'') '

		IF @TinhTrang IS NOT NULL
			SET @cmd = @cmd + N' AND EXISTS(
								SELECT 1 FROM (SELECT Item FROM dbo.Split(@TinhTrang,'','')) T 
								WHERE T.Item =  (CASE WHEN VBDi.[Status] < 0 THEN N''Bị huỷ''
								WHEN VBDi.[Status] = 0 THEN N''Đang soạn''
								WHEN VBDi.[Status] = 4 THEN N''Từ chối''
								WHEN VBDi.[Status] = 10 THEN N''Đã phê duyệt''
								WHEN VBDi.[Status] = 11 THEN N''Chờ phát hành''
								WHEN VBDi.[Status] = 12 THEN N''Đã phát hành''
								ELSE VBDi.StatusText END) 
								) '
	END

	INSERT INTO @tblVBDi
	EXECUTE sp_executesql @cmd,
							N'@Email NVARCHAR(200), 
							@SiteVBUrl VARCHAR(255), 
							@STATUS INT, 
							@FromDateF DATETIME, 
							@ToDateF DATETIME, 
							@IsAdmin BIT, 
							@UserId VARCHAR(50), 
							@sCodeTB NVARCHAR(MAX),
							@TinhTrang NVARCHAR(MAX)',
							@Email = @Email, 
							@SiteVBUrl = @SiteVBUrl, 
							@STATUS = @STATUS, 
							@FromDateF = @FromDateF, 
							@ToDateF = @ToDateF, 
							@IsAdmin = @IsAdmin, 
							@UserId = @UserId, 
							@sCodeTB = @sCodeTB,
							@TinhTrang = @TinhTrang

	IF @LIMIT > 0 AND @IsCount = 0
	BEGIN
		SELECT * 
		FROM @tblVBDi
		--WHERE (@ModuleId IS NULL OR EXISTS (SELECT 1 FROM dbo.Split(@ModuleId,',') WHERE Item = ModuleId))
		ORDER BY Created DESC
		OFFSET @OFFSET ROWS FETCH NEXT @LIMIT ROWS ONLY
	END

	SELECT COUNT(1) AS totalRecord FROM @tblVBDi --WHERE (@ModuleId IS NULL OR EXISTS (SELECT 1 FROM dbo.Split(@ModuleId,',') WHERE Item = ModuleId))
END