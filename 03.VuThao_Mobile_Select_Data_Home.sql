USE Petrolimex_DataeOffice
GO 

IF OBJECT_ID('VuThao_Mobile_Select_Data_Home', 'P') IS NOT NULL DROP PROCEDURE VuThao_Mobile_Select_Data_Home
GO

CREATE PROCEDURE [dbo].[VuThao_Mobile_Select_Data_Home]
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

	DECLARE @tblNotify TABLE (
			[ID] UNIQUEIDENTIFIER,
			[Title] NVARCHAR(500),
			[DocumentID] NUMERIC,
			[TaskID] NUMERIC,
			[Type] BIT,
			[SendUnit] NVARCHAR(255),
			[Priority] TINYINT,
			[Status] TINYINT,
			[Action] NVARCHAR(255),
			[DueDate] DATETIME,
			[Content] NVARCHAR(1000),
			[Percent] NUMERIC,
			[Created] DATETIME,
			[Modified] DATETIME,
			[Read] BIT,
			[TaskCategory] NVARCHAR(255),
			[CategoryText] NVARCHAR(MAX),
			[ModuleId] INT,
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
	
	IF @Action = 'ProcessingNotify' OR @Action = 'VBDenTitle' OR @Action = 'VBDiTitle'
	BEGIN
		SET @cmd = N'SELECT N.ID,N.Title,N.DocumentID,N.TaskID,N.[Type],N.SendUnit,N.[Priority],N.[Status],N.[Action]
						,N.DueDate,N.Content,N.[Percent],N.Created,N.Modified,N.[Read],N.TaskCategory
						,[dbo].[fnc_Notify_GetCategory_Mobile] (N.ListName,N.Category) AS CategoryText
						,[dbo].[fnc_Notify_GetModule_Mobile] (N.ListName,N.Category) AS ModuleId
						, PP.ImagePath, PP.Position--, N.ListName
					FROM [Notify' +   IIF(@CurrentSite = N'', N'', N'_' + @CurrentSite) + N'] N (NOLOCK)
					LEFT JOIN ['+@DBName + @CurrentSite +N']..PersonalProfile PP (NOLOCK) ON PP.AccountName = N.AssignedBy AND PP.UserStatus != -1
					' + CASE WHEN @Action = 'VBDenTitle' AND (ISNULL(@BanLanhDao,'') != '' OR (ISNULL(@TinhTrang,'') != '' AND LOWER(@TinhTrang) != 'tất cả'))
							 THEN N'LEFT JOIN ['+@DBName + @CurrentSite +N']..[VanBanDen] VBDen (NOLOCK) ON VBDen.ID = N.DocumentID ' 
							 ELSE N'' 
						END + N'
					WHERE N.[Status] = @Status
							AND N.[Email] = @Email
							AND N.[Type] = 1
							AND N.[Action] NOT IN (N''Remove'',N''Hủy'',N''Giao việc'')
							AND N.Title NOT LIKE N''Nhận VB đến (phối hợp)%''
							--AND N.[Url] = @SiteVBUrl
					'
		IF @FromDateF IS NOT NULL AND @ToDateF IS NOT NULL
			SET @cmd = @cmd + N' AND N.Created BETWEEN @FromDateF AND @ToDateF'

		IF @FilterText IS NOT NULL
			SET @cmd = @cmd + N' AND (N.TaskCategory LIKE N''%' + @FilterText + '%'' OR N.Content LIKE N''%' + @FilterText + '%'') '

		IF @Action = 'VBDenTitle'
		BEGIN
			SET @ModuleId = '3,5'

			IF ISNULL(@BanLanhDao,'') != ''
				SET @cmd = @cmd + N' AND VBDen.[BanLanhDao] LIKE N''%' + @BanLanhDao + '%'''

			IF ISNULL(@TinhTrang,'') != '' AND LOWER(@TinhTrang) != 'tất cả'
				SET @cmd = @cmd + N' AND VBDen.[TrangThai] = N''' + @TinhTrang + ''''

			--IF ISNULL(@TinhTrang,'') != '' AND LOWER(@TinhTrang) != 'tất cả'
			--	SET @cmd = @cmd + N' AND N.[Action] = N''' + @TinhTrang + ''''
		END

		IF @Action = 'VBDiTitle'
		BEGIN
			SET @ModuleId = '7,9'

			IF ISNULL(@TinhTrang,'') != '' AND LOWER(@TinhTrang) != N'tất cả'
			BEGIN
				IF LOWER(@TinhTrang) = N'chờ phê duyệt'
					SET @cmd = @cmd + N' AND N.[Action] IN (N''Trình LĐ Phòng/Ban'',N''Trình LĐ Phòng'') '
				ELSE IF LOWER(@TinhTrang) = N'đã phê duyệt'
					SET @cmd = @cmd + N' AND N.[Action] = N''Trình LĐ Văn phòng/Ban TCKT'''
				ELSE IF LOWER(@TinhTrang) = N'chờ phát hành'
					SET @cmd = @cmd + N' AND N.[Action] IN (N''Trình LĐ Tập đoàn'',N''Trình lãnh đạo Tập đoàn'',N''Ban TGĐ/HĐQT'') '
			END
		END
	END

	IF @Action = 'PhoiHop'
	BEGIN
		SET @cmd = N'SELECT N.ID,N.Title,N.DocumentID,N.TaskID,N.[Type],N.SendUnit,N.[Priority],N.[Status],N.[Action]
						,N.DueDate,N.Content,N.[Percent],N.Created,N.Modified,N.[Read],N.TaskCategory
						,[dbo].[fnc_Notify_GetCategory_Mobile] (N.ListName,N.Category) AS CategoryText
						,[dbo].[fnc_Notify_GetModule_Mobile] (N.ListName,N.Category) AS ModuleId
						, PP.ImagePath, PP.Position
					FROM [Notify' + IIF(@CurrentSite = N'', N'', N'_' + @CurrentSite) + N'] N (NOLOCK)
					LEFT JOIN ['+@DBName + @CurrentSite +N']..PersonalProfile PP (NOLOCK) ON PP.AccountName = N.AssignedBy AND PP.UserStatus != -1
					WHERE N.[Status] = @Status
							AND N.[Email] = @Email
							AND N.[Type] = 1
							AND N.[Action] NOT IN (N''Remove'',N''Hủy'',N''Giao việc'')
							AND N.[Url] = @SiteVBUrl
							AND N.[Title] LIKE N''Nhận VB đến (phối hợp)%''
					'
		IF @FilterText IS NOT NULL
			SET @cmd = @cmd + N' AND (N.TaskCategory LIKE N''%' + @FilterText + '%'' OR N.Content LIKE N''%' + @FilterText + '%'') '
	END

	IF @Action = 'TCThongBao' OR @Action = 'VBDenThongBao' OR @Action = 'VBDiThongBao'
	BEGIN
		SET @cmd = N'SELECT N.ID,N.Title,N.DocumentID,N.TaskID,N.[Type],N.SendUnit,N.[Priority],N.[Status],N.[Action]
						,N.DueDate,N.Content,N.[Percent],N.Created,N.Modified,N.[Read],N.TaskCategory
						,[dbo].[fnc_Notify_GetCategory_Mobile] (N.ListName,N.Category) AS CategoryText
						,[dbo].[fnc_Notify_GetModule_Mobile] (N.ListName,N.Category) AS ModuleId
						, PP.ImagePath, PP.Position
					FROM [Notify' + IIF(@CurrentSite = N'', N'', N'_' + @CurrentSite) + N'] N (NOLOCK)
					LEFT JOIN ['+@DBName + @CurrentSite +N']..PersonalProfile PP (NOLOCK) ON PP.AccountName = N.AssignedBy AND PP.UserStatus != -1
					' + IIF(@Action = 'VBDenThongBao', N' LEFT JOIN ['+@DBName + @CurrentSite +N']..[VanBanDen] VBDen (NOLOCK)
						ON N.ListName = N''Văn bản đến'' 
						AND (
						(VBDen.ID = N.DocumentID AND N.ItemUrl LIKE ''%/SitePages/VanBanDen%'' )
						OR (N.ItemUrl NOT LIKE ''%vanban/SitePages/VanBanDen%''AND VBDen.ItemId = N.DocumentID)
						)
					', N'') + N'

					' + IIF(@Action = 'VBDiThongBao', N'', N'') + N'

					WHERE N.[Read] = @Status
							AND N.[Email] = @Email
							AND N.[Type] = 0
							AND N.[Action] NOT IN (N''Remove'',N''Hủy'',N''Giao việc'')
							--AND N.[Url] = @SiteVBUrl
					'
		IF @Action = 'TCThongBao' AND @Status = 0
			SET @cmd = @cmd + N' AND N.[Status] = 0'

		IF @FromDateF IS NOT NULL AND @ToDateF IS NOT NULL
			SET @cmd = @cmd + N' AND N.Created BETWEEN @FromDateF AND @ToDateF'

		IF @FilterText IS NOT NULL
			SET @cmd = @cmd + N' AND (N.TaskCategory LIKE N''%' + @FilterText + '%'' OR N.Content LIKE N''%' + @FilterText + '%'') '

		IF @Action = 'VBDenThongBao'
		BEGIN
			IF @BanLanhDao IS NOT NULL
				SET @cmd = @cmd + N' AND VBDen.[BanLanhDao] LIKE N''%' + @BanLanhDao + '%'''

			IF @TinhTrang IS NOT NULL
				SET @cmd = @cmd + N' AND N.[Action] = N''' + @TinhTrang + ''''

			SET @ModuleId = '3,5'
		END

		IF @Action = 'VBDiThongBao'
		BEGIN
			SET @cmd = @cmd + N' AND N.[Title] NOT LIKE N''Nhận VB đến (phối hợp)%'''

			IF @TinhTrang IS NOT NULL
				SET @cmd = @cmd + N' AND EXISTS(SELECT 1 FROM dbo.Split(' + @TinhTrang + N','','') tmp WHERE tmp.Item = N.[Action])'

			SET @ModuleId = '6,7,8,9'
		END
	END

	INSERT INTO @tblNotify
	EXECUTE sp_executesql @cmd,
							N'@Email NVARCHAR(200), @SiteVBUrl VARCHAR(255), @STATUS INT, @FromDateF DATETIME, @ToDateF DATETIME',
							@Email = @Email, @SiteVBUrl = @SiteVBUrl, @STATUS = @STATUS, @FromDateF = @FromDateF, @ToDateF = @ToDateF

	IF @LIMIT > 0 AND @IsCount = 0
	BEGIN
		SELECT * 
		FROM @tblNotify
		WHERE (@ModuleId IS NULL OR EXISTS (SELECT 1 FROM dbo.Split(@ModuleId,',') WHERE Item = ModuleId))
		ORDER BY CASE WHEN @Action = 'ProcessingNotify' AND @STATUS = 1 THEN Created ELSE Modified END DESC
		OFFSET @OFFSET ROWS FETCH NEXT @LIMIT ROWS ONLY
	END

	SELECT COUNT(1) AS totalRecord FROM @tblNotify WHERE (@ModuleId IS NULL OR EXISTS (SELECT 1 FROM dbo.Split(@ModuleId,',') WHERE Item = ModuleId))
END