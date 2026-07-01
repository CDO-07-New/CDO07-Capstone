# API Gateway AI Edge

This module creates an IAM-authenticated HTTP API edge for the AI Engine predict route.

Flow:

```text
Lambda Window Feeder
-> API Gateway HTTP API, route POST /v1/predict, authorization AWS_IAM
-> VPC Link
-> ALB listener
-> AI Engine target group
```

The module does not change the ALB from internet-facing to internal. If the ALB remains public, callers can still bypass API Gateway by calling the ALB DNS name directly. To make API Gateway the only security edge, either make the ALB internal or restrict the ALB listener/security group so only approved sources can reach `/v1/predict`.

HTTP API private integrations use VPC Link for the backend path to ALB. The client-facing API Gateway endpoint is still an API Gateway endpoint, so VPC-attached clients must have a valid route to that endpoint. If there is no NAT path, use an approved private access pattern before applying this broadly.
