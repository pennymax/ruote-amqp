
require 'ruote/part/local_participant'
require 'ruote-amqp'


module RuoteAMQP

  #
  # = AMQP Participants
  #
  # The RuoteAMQP::Participant allows you to send workitems (serialized as
  # JSON) or messages to any AMQP queues right from the process
  # definition. When combined with the RuoteAMQP::Listener you can easily
  # leverage an extremely powerful local/remote participant
  # combinations.
  #
  # By default the participant relies on the presence of an AMQP
  # listener. Workitems are sent and no replies are given to the
  # engine. The participant can be configured to reply to the engine
  # immediately after queueing a message, see the usage section below.
  #
  # == Configuration
  #
  # AMQP configuration is handled by directly manipulating the
  # values of the +AMQP.settings+ hash, as provided by the AMQP
  # gem. No AMQP defaults are set by the participant.
  #
  # == Usage
  #
  # Currently it's possible to send either workitems or messages
  # directly to a specific queue, and have the engine wait for
  # replies on another queue (see AMQPListener).
  #
  # Setting up the participant
  #
  #   engine.register_participant(
  #     :amqp, RuoteAMQP::Participant )
  #
  # Setup a participant that always replies to the engine
  #
  #   engine.register_participant(
  #     :amqp, RuoteAMQP::Participant, :reply_by_default => true )
  #
  # Sending a message example
  #
  #   Ruote.process_definition do
  #     sequence do
  #       amqp :queue => 'test', :message => 'foo'
  #     end
  #   end
  #
  # Sending a workitem
  #
  #   Ruote.process_definition do
  #     sequence do
  #       amqp :queue => 'test'
  #     end
  #   end
  #
  # Let the participant reply to the engine without involving the listener
  #
  #   Ruote.process_definition do
  #     sequence do
  #       amqp :queue => 'test', :reply_anyway => true
  #     end
  #   end
  #
  # When waiting for a reply it only makes sense to send a workitem.
  #
  # == Workitem modifications
  #
  # To ease replies, an additional workitem attribute is set:
  #
  #   'reply_queue'
  #
  # +reply_queue+ has the name of the queue where the RuoteAMQP::Listener
  # expects replies from remote participants
  #
  # == AMQP notes
  #
  # The participant currently only makes use of direct
  # exchanges. Possible future improvements might see use for topic
  # and fanout exchanges as well.
  #
  # The direct exchanges are always marked as durable by the
  # participant, and messages are marked as persistent by default (see
  # #RuoteAMQP)
  #
  class Participant

    include Ruote::LocalParticipant

    # Accepts an options hash with the following keys:
    #
    # * :reply_by_default => (bool) false by default
    # * :default_queue => (string) nil by default
    #
    def initialize( options )

      RuoteAMQP.start!

      @options = {
        'reply_by_default' => false,
        'default_queue' => nil
      }.merge( options.inject( {} ) { |h, ( k, v )| h[k.to_s] = v; h } )
        #
        # the inject is here to make sure that all options have String keys
    end

    # Process the workitem at hand. By default the workitem will be
    # published to the direct exchange specified in the +queue+
    # workitem parameter. You can specify a +message+ workitem
    # parameter to have that sent instead of the workitem.
    #
    # To force the participant to reply to the engine, set the
    # +reply_anyway+ workitem parameter.
    #
    def consume( workitem )
      if target_queue = determine_queue( workitem )

        q = MQ.queue( target_queue, :durable => true )

        opts = {
          :persistent => RuoteAMQP.use_persistent_messages?,
          :content_type => 'application/json' }

        # Message or workitem?
        if message = ( workitem.fields['message'] || workitem.fields['params']['message'] )
          q.publish( message, opts )
        else
          q.publish( encode_workitem( workitem ), opts )
        end
      else
        raise "no queue in workitem params!"
      end

      if @options['reply_by_default'] || workitem.fields['params']['reply_anyway'] == true
        reply_to_engine( workitem )
      end
    end

    def stop
      RuoteAMQP.stop!
    end

    def cancel( fei, flavour )
      #
      # TODO : sending a cancel item is not a bad idea, especially if the
      #        job done over the amqp fence lasts...
      #
    end

    private

    def determine_queue( workitem )

      workitem.fields['params']['queue'] || @options['default_queue']
    end

    # Encode the workitem as JSON
    #
    def encode_workitem( wi )

      Rufus::Json.encode( wi.to_h )
    end
  end
end
