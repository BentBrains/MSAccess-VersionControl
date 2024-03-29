﻿SELECT
  MSysNavPaneGroupCategories.Name AS CategoryName,
  MSysNavPaneGroupCategories.Position AS CategoryPosition,
  MSysNavPaneGroupCategories.Flags AS CategoryFlags,
  MSysNavPaneGroups.Name AS GroupName,
  MSysNavPaneGroups.Flags AS GroupFlags,
  MSysNavPaneGroups.Position AS GroupPosition,
  MSysObjects.Type AS ObjectType,
  MSysObjects.Name AS ObjectName,
  MSysNavPaneGroupToObjects.Flags AS ObjectFlags,
  MSysNavPaneGroupToObjects.Icon AS ObjectIcon,
  MSysNavPaneGroupToObjects.Position AS ObjectPosition,
  MSysNavPaneGroupToObjects.Name AS NameInGroup,
  MSysNavPaneGroupCategories.Id AS CategoryID,
  MSysNavPaneGroups.Id AS GroupID,
  MSysNavPaneGroupToObjects.Id AS LinkID
FROM
  (
    MSysNavPaneGroupCategories
    INNER JOIN MSysNavPaneGroups ON MSysNavPaneGroupCategories.Id = MSysNavPaneGroups.GroupCategoryID
  )
  LEFT JOIN (
    MSysNavPaneGroupToObjects
    LEFT JOIN MSysObjects ON MSysNavPaneGroupToObjects.ObjectID = MSysObjects.Id
  ) ON MSysNavPaneGroups.Id = MSysNavPaneGroupToObjects.GroupID
WHERE
  (
    (
      (MSysNavPaneGroups.Name) Is Not Null
    )
    AND (
      (
        MSysNavPaneGroupCategories.Type
      )= 4
    )
  )
ORDER BY
  MSysNavPaneGroupCategories.Name,
  MSysNavPaneGroups.Name,
  MSysObjects.Type,
  MSysObjects.Name;
