defmodule SiteEncrypt.Application do
  use Application

  def start(_type, _args) do
    Supervisor.start_link(
      [
        SiteEncrypt.Registry,
        AcmeServer.Db,
        AcmeServer.Jobs
      ],
      strategy: :one_for_one,
      name: SiteEncrypt.Supervisor
    )
  end
end
