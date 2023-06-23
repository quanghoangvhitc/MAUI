USE Petrolimex_DataeOffice
GO 

IF OBJECT_ID('VuThao_Mobile_Select_Data_Action', 'P') IS NOT NULL DROP PROCEDURE VuThao_Mobile_Select_Data_Action
GO

CREATE PROCEDURE [dbo].[VuThao_Mobile_Select_Data_Action]
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

	DECLARE @NotifyId NVARCHAR(50) = NULL
	DECLARE @ItemId BIGINT = NULL
	DECLARE @ModuleId TINYINT = NULL
	DECLARE @DBName NVARCHAR(150) = (SELECT TOP 1 [VALUE] FROM Settings WHERE [KEY] = 'DBSite')
	DECLARE @Modified DATETIME = NULL
	DECLARE @ModifiedF DATETIME = NULL
	DECLARE @IsArchived BIT = 0
	DECLARE @SiteUrl NVARCHAR(255) = N''
	DECLARE @ListName NVARCHAR(255) = N''
	DECLARE @AssignedToText NVARCHAR(255) = NULL
	DECLARE @CreatedBy NVARCHAR(50) = NULL
	DECLARE @NguoiNhan NVARCHAR(255) = NULL

	IF (SELECT MAX(ParentID) FROM @tbl@Parameters GROUP BY ParentID) = 1
	BEGIN
		SELECT @ItemId = IIF(ISNULL(ItemId,'') = '', NULL , ItemId)
			, @NotifyId = IIF(ISNULL(NotifyId,'') = '', NULL , NotifyId)
			, @ModuleId = IIF(ISNULL(ModuleId,'') = '', NULL , ModuleId)
			, @IsArchived = ISNULL(IsArchived,0)
			, @SiteUrl = ISNULL(SiteUrl,N'')
			, @ListName = ISNULL(ListName,N'')
			, @AssignedToText = IIF(ISNULL(AssignedToText,'') = '', NULL , AssignedToText)
			, @CreatedBy = IIF(ISNULL(CreatedBy,'') = '', NULL , CreatedBy)
			, @NguoiNhan = IIF(ISNULL(NguoiNhan,'') = '', NULL , NguoiNhan)
		FROM @tbl@Parameters SRC
		PIVOT(MAX([Value]) FOR [Key] IN (ItemId,NotifyId,ModuleId,IsArchived,SiteUrl,ListName,AssignedToText,CreatedBy,NguoiNhan)) PIV;
	END

	IF @Modified IS NOT NULL
		SET @ModifiedF = [dbo].fnFormatDate(@Modified,'YYYY/MM/DD HH:MI:SS');

	IF @Action = 'UpdateNotifyAsRead'
	BEGIN
		SET @cmd = N'EXEC vuthao_UpdateNotifyStatus @ID = @NotifyId, @Site = @CurrentSite'
		EXEC sp_executesql @cmd,
							N'@NotifyId VARCHAR(50), @CurrentSite VARCHAR(100)',
							@NotifyId = @NotifyId, @CurrentSite = @CurrentSite

		RETURN;
	END

	IF @Action = 'GetNotifyById'
	BEGIN
		SET @cmd = N'SELECT N.DocumentID,N.TaskID
						,[dbo].[fnc_Notify_GetModule_Mobile] (N.ListName,N.Category) AS ModuleId
					FROM [Notify' +   IIF(@CurrentSite = N'', N'', N'_' + @CurrentSite) + N'] N (NOLOCK)
					WHERE N.ID = @NotifyId
					'
		EXEC sp_executesql @cmd,
							N'@NotifyId VARCHAR(50)',
							@NotifyId = @NotifyId

		RETURN;
	END

	IF @Action = 'VBDenTaskJson'
	BEGIN
		SET @cmd = N'
			;WITH CTE AS
			(
				SELECT T.[ID],T.[VBId],T.[ParentId],T.[DeThucHien],T.[DueDate],T.[TrangThai], D.Title AS DepartmentTitle, T.Created
					, TP.[UserType] AS [AssignedToType]
					,CASE WHEN TP.[UserType] = 0 THEN U.FullName ELSE G.Title END AS [Name]
					,CASE WHEN TP.[UserType] = 0 THEN U.Position ELSE NULL END AS [Position]
					,CASE WHEN TP.[UserType] = 0 THEN U.ImagePath ELSE NULL END AS [ImagePath]
				FROM ['+@DBName + @CurrentSite +N']..[TaskVBDen] T WITH (NOLOCK INDEX(idx_TaskVBDen_SelectByVBId))  
				LEFT JOIN ['+@DBName + @CurrentSite +N']..[Department] D (NOLOCK) ON  D.ID = T.DepartmentId
				LEFT JOIN (SELECT ModuleId,[Name],MIN(ID) ID FROM ['+@DBName + @CurrentSite +N']..[UserField] GROUP BY ModuleId, [Name]) UF ON UF.ModuleId = T.ModuleId AND UF.[Name] = ''AssignedTo''
				LEFT JOIN ['+@DBName + @CurrentSite +N']..[TaskVBDenPermission] TP WITH (NOLOCK) 
					ON TP.TaskId = T.ID AND TP.UserFieldId & UF.ID > 0
				LEFT JOIN ['+@DBName + @CurrentSite +N']..[PersonalProfile] U WITH (NOLOCK) ON TP.[UserType] = 0 AND U.ID = TP.UserId
				LEFT JOIN ['+@DBName + @CurrentSite +N']..[Group] G WITH (NOLOCK) ON TP.[UserType] = 1 AND G.ID = TP.UserId
				WHERE T.[VBId] = @ItemId
				AND (@ModifiedF IS NULL OR T.[Modified] >= @ModifiedF)	
			)
			SELECT CTE.[ID], CTE.[VBId], CTE.[ParentId], CTE.[DeThucHien], CTE.[DueDate],CTE.[TrangThai], CTE.[AssignedToType], CTE.[Position], CTE.[ImagePath]
				,CASE WHEN ISNULL(CTE.[Name],'''') != '''' THEN CTE.[Name] ELSE CTE.[DepartmentTitle] END AS [DepartmentTitle]
			FROM CTE
			ORDER BY CTE.Created ASC
		'

		EXEC sp_executesql @cmd,
							N'@ItemId BIGINT, @ModifiedF DATETIME',
							@ItemId = @ItemId,
							@ModifiedF = @ModifiedF
		
		RETURN;
	END

	IF @Action = 'VBDenTaskById'
	BEGIN
		SET @cmd = N'
			;WITH CTE AS
			(
				SELECT T.*, D.Title AS DepartmentTitleTmp
					, TP.[UserType] AS [AssignedToType]
					,CASE WHEN TP.[UserType] = 0 THEN U.FullName ELSE G.Title END AS [Name]
					,CASE WHEN TP.[UserType] = 0 THEN U.Position ELSE NULL END AS [Position]
					,CASE WHEN TP.[UserType] = 0 THEN U.ImagePath ELSE NULL END AS [ImagePath]
				FROM ['+@DBName + @CurrentSite +N']..[TaskVBDen] T WITH (NOLOCK)  
				LEFT JOIN ['+@DBName + @CurrentSite +N']..[Department] D (NOLOCK) ON  D.ID = T.DepartmentId
				LEFT JOIN (SELECT ModuleId,[Name],MIN(ID) ID FROM ['+@DBName + @CurrentSite +N']..[UserField] GROUP BY ModuleId, [Name]) UF ON UF.ModuleId = T.ModuleId AND UF.[Name] = ''AssignedTo''
				LEFT JOIN ['+@DBName + @CurrentSite +N']..[TaskVBDenPermission] TP WITH (NOLOCK) 
					ON TP.TaskId = T.ID AND TP.UserFieldId & UF.ID > 0
				LEFT JOIN ['+@DBName + @CurrentSite +N']..[PersonalProfile] U WITH (NOLOCK) ON TP.[UserType] = 0 AND U.ID = TP.UserId
				LEFT JOIN ['+@DBName + @CurrentSite +N']..[Group] G WITH (NOLOCK) ON TP.[UserType] = 1 AND G.ID = TP.UserId
				WHERE T.[ID] = @ItemId
			)
			SELECT TOP 1 CTE.*,CASE WHEN ISNULL(CTE.[Name],'''') != '''' THEN CTE.[Name] ELSE CTE.[DepartmentTitleTmp] END AS [DepartmentTitle]
			FROM CTE
			ORDER BY CTE.Created ASC
		'

		EXEC sp_executesql @cmd,
							N'@ItemId BIGINT',
							@ItemId = @ItemId
		
		RETURN;
	END

	IF @Action = 'VBBHTaskJson'
	BEGIN
		SET @cmd = N'
			;WITH CTE AS
			(
				SELECT T.[ID],T.[VBId],T.[ParentId],T.[DeThucHien],T.[DueDate],T.[TrangThai], D.Title AS DepartmentTitle, T.Created
					, TP.[UserType] AS [AssignedToType]
					,CASE WHEN TP.[UserType] = 0 THEN U.FullName ELSE G.Title END AS [Name]
					,CASE WHEN TP.[UserType] = 0 THEN U.Position ELSE NULL END AS [Position]
					,CASE WHEN TP.[UserType] = 0 THEN U.ImagePath ELSE NULL END AS [ImagePath]
				FROM ['+@DBName + @CurrentSite +N']..[TaskVBDi] T WITH (NOLOCK INDEX(idx_TaskVBDi_SelectByVBId))  
				LEFT JOIN ['+@DBName + @CurrentSite +N']..[Department] D (NOLOCK) ON  D.ID = T.DepartmentId
				LEFT JOIN (SELECT ModuleId,[Name],MIN(ID) ID FROM ['+@DBName + @CurrentSite +N']..[UserField] GROUP BY ModuleId, [Name]) UF ON UF.ModuleId = T.ModuleId AND UF.[Name] = ''AssignedTo''
				LEFT JOIN ['+@DBName + @CurrentSite +N']..[TaskVBDiPermission] TP WITH (NOLOCK) 
					ON TP.TaskId = T.ID AND TP.UserFieldId & UF.ID > 0
				LEFT JOIN ['+@DBName + @CurrentSite +N']..[PersonalProfile] U WITH (NOLOCK) ON TP.[UserType] = 0 AND U.ID = TP.UserId
				LEFT JOIN ['+@DBName + @CurrentSite +N']..[Group] G WITH (NOLOCK) ON TP.[UserType] = 1 AND G.ID = TP.UserId
				WHERE T.[VBId] = @ItemId
				AND (@ModifiedF IS NULL OR T.[Modified] >= @ModifiedF)	
			)
			SELECT CTE.[ID], CTE.[VBId], CTE.[ParentId], CTE.[DeThucHien], CTE.[DueDate],CTE.[TrangThai], CTE.[AssignedToType], CTE.[Position], CTE.[ImagePath]
				,CASE WHEN ISNULL(CTE.[Name],'''') != '''' THEN CTE.[Name] ELSE CTE.[DepartmentTitle] END AS [DepartmentTitle]
			FROM CTE
			ORDER BY CTE.Created ASC
		'

		EXEC sp_executesql @cmd,
							N'@ItemId BIGINT, @ModifiedF DATETIME',
							@ItemId = @ItemId,
							@ModifiedF = @ModifiedF
		
		RETURN;
	END

	IF @Action = 'VBBHTaskById'
	BEGIN
		SET @cmd = N'
			;WITH CTE AS
			(
				SELECT T.*, D.Title AS DepartmentTitleTmp
					, TP.[UserType] AS [AssignedToType]
					,CASE WHEN TP.[UserType] = 0 THEN U.FullName ELSE G.Title END AS [Name]
					,CASE WHEN TP.[UserType] = 0 THEN U.Position ELSE NULL END AS [Position]
					,CASE WHEN TP.[UserType] = 0 THEN U.ImagePath ELSE NULL END AS [ImagePath]
				FROM ['+@DBName + @CurrentSite +N']..[TaskVBDi] T WITH (NOLOCK INDEX(idx_TaskVBDi_SelectByVBId))  
				LEFT JOIN ['+@DBName + @CurrentSite +N']..[Department] D (NOLOCK) ON  D.ID = T.DepartmentId
				LEFT JOIN (SELECT ModuleId,[Name],MIN(ID) ID FROM ['+@DBName + @CurrentSite +N']..[UserField] GROUP BY ModuleId, [Name]) UF ON UF.ModuleId = T.ModuleId AND UF.[Name] = ''AssignedTo''
				LEFT JOIN ['+@DBName + @CurrentSite +N']..[TaskVBDiPermission] TP WITH (NOLOCK) 
					ON TP.TaskId = T.ID AND TP.UserFieldId & UF.ID > 0
				LEFT JOIN ['+@DBName + @CurrentSite +N']..[PersonalProfile] U WITH (NOLOCK) ON TP.[UserType] = 0 AND U.ID = TP.UserId
				LEFT JOIN ['+@DBName + @CurrentSite +N']..[Group] G WITH (NOLOCK) ON TP.[UserType] = 1 AND G.ID = TP.UserId
				WHERE T.[ID] = @ItemId
			)
			SELECT TOP 1 CTE.*,CASE WHEN ISNULL(CTE.[Name],'''') != '''' THEN CTE.[Name] ELSE CTE.[DepartmentTitleTmp] END AS [DepartmentTitle]
			FROM CTE
			ORDER BY CTE.Created ASC
		'

		EXEC sp_executesql @cmd,
							N'@ItemId BIGINT',
							@ItemId = @ItemId
		
		RETURN;
	END

	IF @Action = 'VBTaskByIdUserRole'
	BEGIN
		SET @cmd = N'SELECT TOP 1 P.*, P.FullName AS Title
				FROM ['+@DBName + @CurrentSite +N']..[PersonalProfile] P
				WHERE (@AssignedToText IS NOT NULL AND P.FullName LIKE N''%''+@AssignedToText+''%'')
				OR (@CreatedBy IS NOT NULL AND P.ID = @CreatedBy)
				OR (@NguoiNhan IS NOT NULL AND P.FullName = @NguoiNhan)
				'
		EXEC sp_executesql @cmd,
							N'@AssignedToText NVARCHAR(255), @CreatedBy NVARCHAR(50), @NguoiNhan NVARCHAR(255)',
							@AssignedToText = @AssignedToText,
							@CreatedBy = @CreatedBy,
							@NguoiNhan = @NguoiNhan

		RETURN;
	END

	IF @Action = 'VBDenUserShare' OR @Action = 'VBDiUserShare' OR @Action = 'VBBHUserShare'
	BEGIN
		 SET @cmd = N';WITH CTE AS
		 (
			SELECT  W.ID,W.Note,W.Created
			FROM ['+@DBName + @CurrentSite +N'].[Workflow].WorkflowInfo W WITH (NOLOCK)
			WHERE W.ItemId = @ItemId And W.ModuleId = @ModuleId
		 )
		 SELECT ROW_NUMBER() OVER(ORDER BY(SELECT 1)) STT, CTE.Note AS [Value], CTE.Created , PP.FullName AS Title, PP.Position, PP.ImagePath
		 FROM CTE
		 LEFT JOIN ['+@DBName + @CurrentSite +N'].[Workflow].[WorkflowInfoUser] WU WITH (NOLOCK) ON WU.WorkflowInfoId = CTE.ID
		 LEFT JOIN ['+@DBName + @CurrentSite +N']..PersonalProfile PP WITH (NOLOCK) ON WU.UserType = 0 AND WU.UserId = Pp.ID 
			OR EXISTS(SELECT 1 FROM ['+@DBName + @CurrentSite +N']..UserInGroup UG WITH (NOLOCK) WHERE UG.GroupId = WU.UserId AND WU.UserType = 1 AND UG.UserId = PP.ID)
		ORDER BY CTE.Created
		'

		EXEC sp_executesql @cmd,
							N'@ItemId BIGINT, @ModuleId TINYINT',
							@ItemId = @ItemId,
							@ModuleId = @ModuleId

		RETURN;
	END

	IF @Action = 'VBGetViewer'
	BEGIN
		IF @ModuleId IN (3,5)
		BEGIN
			SET @cmd = N'
				SELECT IIF(NX.UserName IS NOT NULL,NX.UserName,UC.FullName) AS Title
				 , UC.Position, UC.ImagePath, NX.Created  
				 FROM ['+@DBName + @CurrentSite +N']..VanBanDenNguoiXem NX WITH (NOLOCK INDEX(idx_VanBanDenNguoiXem_Select))  
				 LEFT JOIN ['+@DBName + @CurrentSite +N']..[PersonalProfile] UC WITH (NOLOCK) ON UC.ID = NX.UserId  
				 WHERE [VBId] = @ItemId
				 ORDER BY NX.Created DESC
				 '
		END
		ELSE
		BEGIN
			SET @cmd = N'
				 SELECT IIF(NX.UserName IS NOT NULL,NX.UserName,UC.FullName) AS Title
				 , UC.Position, UC.ImagePath, NX.Created  
				 FROM ['+@DBName + @CurrentSite +N']..VanBanBanHanhNguoiXem NX WITH (NOLOCK INDEX(idx_VanBanBanHanhNguoiXem_Select))  
				 LEFT JOIN ['+@DBName + @CurrentSite +N']..[PersonalProfile] UC WITH (NOLOCK) ON UC.ID = NX.UserId  
				 WHERE [VBId] = @ItemId
				 AND UC.FullName NOT LIKE N''test%''
				 ORDER BY NX.Created DESC
			'
		END

		EXEC sp_executesql @cmd,
							N'@ItemId BIGINT',
							@ItemId = @ItemId

		RETURN;
	END

	IF @Action = 'VBDenGetWorkflowHistory'
	BEGIN
		SET @cmd = N'
				SELECT  DISTINCT TOP (1000) V.[UserName], V.[Action], V.[Created]
					, IIF(ISNULL(P.Position,'''')<>'''',P.Position, PN.Position ) AS Position
					, IIF(ISNULL(P.ImagePath,'''')<>'''',P.ImagePath, PN.ImagePath ) AS ImagePath
				FROM ['+@DBName + @CurrentSite +N']..[VanBanDenLuanChuyen] V	
				LEFT JOIN ['+@DBName + @CurrentSite +N']..[PersonalProfile] P ON P.ID = V.UserId
				LEFT JOIN ['+@DBName + @CurrentSite +N']..[PersonalProfile] PN ON PN.FullName = V.UserName
				WHERE V.VBId = @ItemId
				ORDER BY V.Created ASC'

		EXEC sp_executesql @cmd,
							N'@ItemId BIGINT',
							@ItemId = @ItemId

		RETURN;
	END

	IF @Action = 'VBDiGetWorkflowHistory'
	BEGIN
		Set @cmd = N'SELECT TB1.[CompletedDate],TB1.[Note],TB1.[Created],TB1.[Email]
					,CASE WHEN TB1.[Category] = N''Phiếu chuyển'' AND [Step] = 5 AND TB1.[Status] = 1  THEN N''Duyệt'' ELSE TB1.[SubmitAction] END AS [SubmitAction]
					, TB2.FullName AS AssignedTo, TB2.Position, TB2.ImagePath
					,REPLACE(TB1.[Action],''Recall '',N''Thu hồi '') as GroupText				
									FROM [dbo].[Notify' + IIF(@IsArchived = 0,N'',N'Archive') + IIF(@CurrentSite = '', @CurrentSite, '_' + @CurrentSite) + N'] TB1 WITH (NOLOCK)
									INNER JOIN PersonalProfile TB2 WITH (NOLOCK) ON TB1.Email = TB2.AccountName
									LEFT JOIN Department TB3 WITH (NOLOCK) ON TB2.DepartmentID = TB3.ID AND TB3.[SiteName] = '''+@CurrentSite+N'''
									WHERE [DocumentID] = @ItemId
									AND ((''' + @SiteUrl + ''' = N'''') OR (TB1.[URL] = ''' + @SiteUrl + N'''))
									AND [ListName] = N''' + @ListName + N'''
									AND [ListName] <> N''List Văn bản đi''
									AND (([Status] = 0) OR (([Status] = 1) AND ([EmailUpdate]=TB1.[Email])))
									AND [Action] <> N''Hủy'''
		EXEC sp_executesql @cmd,
							N'@ItemId BIGINT',
							@ItemId = @ItemId

		RETURN;
	END

	IF @Action = 'VBBHGetWorkflowHistory'
	BEGIN
		SET @cmd = N'
				SELECT  DISTINCT TOP (1000) V.[UserName], V.[Action], V.[Created]
					, IIF(ISNULL(P.Position,'''')<>'''',P.Position, PN.Position ) AS Position
					, IIF(ISNULL(P.ImagePath,'''')<>'''',P.ImagePath, PN.ImagePath ) AS ImagePath
				FROM ['+@DBName + @CurrentSite +N']..[VanBanBanHanhLuanChuyen] V	
				LEFT JOIN ['+@DBName + @CurrentSite +N']..[PersonalProfile] P ON P.ID = V.UserId
				LEFT JOIN ['+@DBName + @CurrentSite +N']..[PersonalProfile] PN ON PN.FullName = V.UserName
				WHERE V.VBId = @ItemId
				ORDER BY V.Created ASC'

		EXEC sp_executesql @cmd,
							N'@ItemId BIGINT',
							@ItemId = @ItemId

		RETURN;
	END
END