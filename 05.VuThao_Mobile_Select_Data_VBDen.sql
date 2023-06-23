USE FPTPetro_DataeOffice
GO

IF OBJECT_ID('VuThao_Mobile_Select_Data_VBDen', 'P') IS NOT NULL DROP PROCEDURE VuThao_Mobile_Select_Data_VBDen
GO

CREATE PROCEDURE [dbo].[VuThao_Mobile_Select_Data_VBDen]
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

	DECLARE @tblVBDen TABLE (
			[ID] BIGINT,
			[Title] NVARCHAR(150),
			[SoDen] NVARCHAR(150),
			[DocumentType] NVARCHAR(255),
			[DueDate] DATE,
			[CoQuanGui] NVARCHAR(255),
			[CoQuanGuiText] NVARCHAR(255),
			[DoKhan] NVARCHAR(50),
			[TrangThai] NVARCHAR(100),
			[Step] TINYINT,
			[TrichYeu] NVARCHAR(4000),
			[BanLanhDao] NVARCHAR(255),
			[ListName] NVARCHAR(50),
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

	IF ISNULL(@IsAdmin, 0) = 0
	BEGIN
		SET @cmd = N'SET @IsAdmin = ISNULL(
			(SELECT TOP 1 1 FROM [' + @DBName + N'].PLX.ResoureGroup NOLOCK
			WHERE ModuleId IN (3,5)
			AND (UserId = @UserId OR UserId LIKE CONCAT(''%'',@UserId,''%''))
			),0)'

		EXECUTE sp_executesql   @cmd,
								N'@UserId VARCHAR(50),@IsAdmin BIT OUT ',
								@UserId = @UserId,@IsAdmin = @IsAdmin OUT
	END
	
	SET @cmd = N'
				IF ISNULL(@IsAdmin, 0) = 0
				BEGIN
					DECLARE @UserTable TABLE(ID uniqueidentifier,PRIMARY KEY (ID));
					DECLARE @DocId TABLE(ID BIGINT, PRIMARY KEY (ID DESC));
					INSERT INTO @UserTable ([ID]) VALUES(@UserId)
					INSERT INTO @UserTable SELECT [GroupId] FROM ['+@DBName + @CurrentSite +N'].[dbo].[UserInGroup] WITH (NOLOCK) WHERE [UserId] = @UserId
					DECLARE @UserCount int = (SELECT COUNT(ID) FROM @UserTable)

					INSERT INTO @DocId
					SELECT DISTINCT [VBId] 
					FROM ['+@DBName + @CurrentSite +N']..[VanBanDenPermission] VBP (NOLOCK)
					WHERE --UserID IN (SELECT [ID] FROM @UserTable)
					((@UserCount <= 15 AND VBP.UserId IN (SELECT ID FROM @UserTable)) OR
					(@UserCount > 15 AND EXISTS(SELECT TOP 1 1 FROM @UserTable U WHERE U.ID = VBP.UserId)))
					--ORDER BY VBP.VBId DESC
				END

				SELECT VBDen.[ID],VBDen.[Title],VBDen.[SoDen],VBDen.[DocumentType],VBDen.[DueDate],VBDen.[CoQuanGui]
						,VBDen.[CoQuanGuiText],VBDen.[DoKhan],VBDen.[TrangThai],VBDen.[Step],VBDen.[TrichYeu]
						,VBDen.[BanLanhDao],VBDen.[ListName],VBDen.[Created],VBDen.[Modified]
						, PP.ImagePath, PP.Position
				FROM ['+@DBName + @CurrentSite +N']..VanBanDen VBDen (NOLOCK)
				LEFT JOIN ['+@DBName + @CurrentSite +N']..PersonalProfile PP (NOLOCK) ON PP.ID = VBDen.ModifiedBy
				WHERE (@IsAdmin=1 OR EXISTS(SELECT TOP 1 1 FROM @DocId WHERE ID = VBDen.ID))
				'
	IF @Action != 'VBDenTatCa'
	BEGIN
		IF @Action = 'VBDenChoChoYKien'
		BEGIN
			SET @cmd = @cmd +  N' AND VBDen.TrangThai = N''Trình Lãnh đạo'''
		END

		IF @Action = 'VBDenDaGiaiQuyet'
		BEGIN
			SET @cmd = @cmd +  N' AND VBDen.TrangThai = N''Hoàn tất'''
		END

		IF @Action = 'VBDenChoThucHien'
		BEGIN
			SET @cmd = @cmd +  N' AND VBDen.TrangThai IN (N''Văn bản từ cơ quan, đơn vị'',N''Văn bản từ trục'', N''Thu hồi'',N''Văn bản từ Tập đoàn'',N''Văn bản từ Tổng công ty'',N''Chuyển đơn vị'')'
		END
	END

	IF @FromDateF IS NOT NULL AND @ToDateF IS NOT NULL
		SET @cmd = @cmd + N' AND VBDen.Created BETWEEN @FromDateF AND @ToDateF'

	IF @FilterText IS NOT NULL
		SET @cmd = @cmd + N' AND (VBDen.TrichYeu LIKE N''%' + @FilterText + '%'' OR VBDen.Title LIKE N''%' + @FilterText + '%'') '

	IF @BanLanhDao IS NOT NULL
		SET @cmd = @cmd + N' AND VBDen.[BanLanhDao] LIKE N''%' + @BanLanhDao + '%'''

	IF @TinhTrang IS NOT NULL
		SET @cmd = @cmd + N' AND VBDen.[TrangThai] = N''' + @TinhTrang + ''''

	INSERT INTO @tblVBDen
	EXECUTE sp_executesql @cmd,
							N'@Email NVARCHAR(200), @SiteVBUrl VARCHAR(255), @STATUS INT, @FromDateF DATETIME, @ToDateF DATETIME,@IsAdmin BIT,@UserId VARCHAR(50)',
							@Email = @Email, @SiteVBUrl = @SiteVBUrl, @STATUS = @STATUS, @FromDateF = @FromDateF, @ToDateF = @ToDateF,@IsAdmin = @IsAdmin,@UserId = @UserId

	IF @LIMIT > 0 AND @IsCount = 0
	BEGIN
		SELECT * 
		FROM @tblVBDen
		--WHERE (@ModuleId IS NULL OR EXISTS (SELECT 1 FROM dbo.Split(@ModuleId,',') WHERE Item = ModuleId))
		ORDER BY CREATED DESC
		OFFSET @OFFSET ROWS FETCH NEXT @LIMIT ROWS ONLY
	END

	SELECT COUNT(1) AS totalRecord FROM @tblVBDen --WHERE (@ModuleId IS NULL OR EXISTS (SELECT 1 FROM dbo.Split(@ModuleId,',') WHERE Item = ModuleId))
END