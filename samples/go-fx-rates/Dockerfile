FROM golang:1.27.3@sha256:e519d3b0a5b285e5aa53ab9eef02bc6bbb9cb04608389b743a136a9ce75f0d1e AS build
WORKDIR /workspace
ENV CGO_ENABLED=0 GOTOOLCHAIN=local
COPY go.mod ./
COPY *.go ./
RUN go vet ./... && go test ./... && go build -trimpath -ldflags="-s -w" -o /fx-rates .

FROM gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab
COPY --from=build /fx-rates /fx-rates
USER 65532:65532
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 CMD ["/fx-rates", "-healthcheck"]
ENTRYPOINT ["/fx-rates"]
