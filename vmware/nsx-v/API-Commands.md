# Delete Stuck Controller
```
sudo curl -sik -u "admin" -H ‘Content-Type: application/xml’ -X GET https://172.29.129.2/api/2.0/vdn/controller | tidy -xml -indent -quiet
curl -sik -u admin -H ‘Content-Type: application/xml’ -X DELETE https://172.29.129.2/api/2.0/vdn/controller/controller-2?forceRemoval=True
```
