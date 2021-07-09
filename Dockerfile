FROM golang:1.11 as builder
WORKDIR /mock-extension-apiserver
COPY . .
RUN make build

FROM alpine:latest as mock-extension-apiserver
WORKDIR /
COPY --from=builder mock-extension-apiserver/bin/mock-extension-apiserver /bin/mock-extension-apiserver
EXPOSE 8080
EXPOSE 5443
CMD ["/bin/mock-extension-apiserver"]
