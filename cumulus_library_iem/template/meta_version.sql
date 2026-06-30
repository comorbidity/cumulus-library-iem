CREATE  TABLE   {{ prefix }}__meta_version AS
SELECT  {{ data_package_version }} AS data_package_version;
