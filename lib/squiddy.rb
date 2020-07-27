require 'trello'

require_relative 'squiddy/event'
require_relative 'squiddy/pull_request'
require_relative 'squiddy/trello'

module Squiddy
  # TrelloPullRequest automatically creates a checklist on a Trello card called
  # "Pull Requests", and adds the pull request URL as an item.
  #
  # If the Pull Request is in a closed state, then it marks the item as
  # complete
  class TrelloPullRequest
    def self.run
      event = Squiddy::Event.new

      return nil unless event.type == "pull_request"

      pull_request = Squiddy::PullRequest.new(event.repository, event.pull_request_number)

      trello_regex = /https:\/\/trello\.com\/c\/\w+/

      trello_card = pull_request.body_regex(trello_regex)
      return nil unless trello_card

      begin
        trello = Squiddy::Trello::Checklist.new(trello_card)

        item = pull_request.url

        if pull_request.open?
          trello.create_checklist unless trello.checklist_exist?

          trello.add_item(item) unless trello.item_exist?(item)
        end

        if pull_request.closed?
          trello.mark_item_as_complete(item) if trello.item_exist?(item)
        end
      rescue Squiddy::Trello::Checklist::ChecklistNotFound => e
        e.message
      end
    end
  end

  # TrelloDependabot will create a card on a specific board and list for every
  # pull request which has a specific label that is configured in dependabot,
  # with the body and link to the PR
  class TrelloDependabot
    def self.run(board_id:,list_create_id:,list_done_id:,github_label:)
      event = Squiddy::Event.new
      return nil unless event.type == "pull_request"

      pull_request = Squiddy::PullRequest.new(event.repository, event.pull_request_number)
      return nil unless pull_request.labels.include?(github_label)

      board = ::Trello::Board.find(board_id)
      card = board.cards.find { |card| card.name == pull_request.title }

      if pull_request.open?
        return nil if card

        dependabot_label = board.labels.find {|label| label.name == "Dependabot" } || ::Trello::Label.create(board_id: board_id, name: "Dependabot")

        body = [pull_request.body, pull_request.url].join('\n')

        ::Trello::Card.create(list_id: list_create_id, name: pull_request.title, desc: body, card_labels: [dependabot_label], pos: "bottom")
      end

      if pull_request.closed?
        return nil unless card

        card.move_to_list(list_done_id)
      end
    end
  end
end
